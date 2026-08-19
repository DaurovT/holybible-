"""Проверка App Attest — доказательства, что запрос идёт из нашего приложения.

Общий секрет в бандле защищает ровно до первого, кто разберёт .ipa: секрет там
один на все копии, отозвать его можно только сменив у всех сразу. App Attest
устроен иначе: устройство заводит ключ в защищённом элементе, Apple заверяет
его сертификатом, и наружу ключ не выходит вообще. Проверив заверение, мы
знаем, что говорим с подлинной сборкой нашего приложения на настоящем iPhone.

Порядок такой:

1. приложение просит челлендж — случайные 32 байта, одноразовые;
2. один раз за установку присылает заверение ключа (`register`);
3. дальше на каждый разбор подписывает свежий челлендж этим ключом (`assert`),
   получает короткоживущий пропуск и идёт с ним в `/explain`.

Разбор заверения — по документации Apple «Validating Apps That Connect to Your
Server». Шаги пронумерованы там же.
"""

import hashlib
import logging
import os
import struct

import cbor2
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import Prehashed

log = logging.getLogger('attest')

# Расширение сертификата, в котором Apple повторяет наш челлендж.
NONCE_OID = x509.ObjectIdentifier('1.2.840.113635.100.8.2')

# Значение aaguid: на боевых сборках одно, на собранных из Xcode — другое.
AAGUID_PROD = b'appattest\x00\x00\x00\x00\x00\x00\x00'
AAGUID_DEV = b'appattestdevelop'

ROOT_CA_PATH = os.path.join(os.path.dirname(__file__),
                            'apple_app_attest_root_ca.pem')


class AttestError(Exception):
    """Заверение или подпись не сошлись. Текст пишется в журнал, не читателю."""


def _der_walk(data: bytes) -> bytes:
    """Достаёт из DER-расширения octet string с нонсом.

    Структура у Apple простая — SEQUENCE { [1] { OCTET STRING nonce } }, — но
    разбирать её вручную по смещениям хрупко: длины бывают в разной форме.
    Идём по тегам и берём последнюю строку из 32 байт.
    """
    found: list[bytes] = []

    def walk(buf: bytes) -> None:
        i = 0
        while i + 2 <= len(buf):
            tag = buf[i]
            length = buf[i + 1]
            i += 2
            if length & 0x80:
                n = length & 0x7F
                if n == 0 or i + n > len(buf):
                    return
                length = int.from_bytes(buf[i:i + n], 'big')
                i += n
            if i + length > len(buf):
                return
            body = buf[i:i + length]
            if tag == 0x04 and length == 32:
                found.append(body)
            elif tag & 0x20:  # составной тег — заходим внутрь
                walk(body)
            i += length

    walk(data)
    if not found:
        raise AttestError('в сертификате нет нонса')
    return found[-1]


def _verify_chain(chain: list[x509.Certificate]) -> None:
    """Сертификат ключа должен цепочкой сходиться к корню Apple."""
    with open(ROOT_CA_PATH, 'rb') as f:
        root = x509.load_pem_x509_certificate(f.read())
    for cert, issuer in zip(chain, chain[1:] + [root]):
        try:
            cert.verify_directly_issued_by(issuer)
        except Exception as e:  # noqa: BLE001 — причина уходит в журнал целиком
            raise AttestError(f'цепочка сертификатов не сходится: {e}') from e


def _public_key_bytes(cose: dict) -> bytes:
    """Несжатая точка кривой: 0x04 || x || y. Из неё же считается keyId."""
    x, y = cose[-2], cose[-3]
    if len(x) != 32 or len(y) != 32:
        raise AttestError('ключ не P-256')
    return b'\x04' + x + y


def _load_key(raw: bytes) -> ec.EllipticCurvePublicKey:
    return ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw)


def _parse_auth_data(auth: bytes, with_credential: bool) -> dict:
    if len(auth) < 37:
        raise AttestError('authenticatorData короче положенного')
    out = {
        'rp_id_hash': auth[:32],
        'flags': auth[32],
        'counter': struct.unpack('>I', auth[33:37])[0],
    }
    if with_credential:
        if len(auth) < 55:
            raise AttestError('нет данных о ключе')
        out['aaguid'] = auth[37:53]
        cred_len = struct.unpack('>H', auth[53:55])[0]
        out['credential_id'] = auth[55:55 + cred_len]
        out['cose_key'] = cbor2.loads(auth[55 + cred_len:])
    return out


class AppAttest:
    def __init__(self, team_id: str, bundle_id: str, environment: str) -> None:
        self.app_id = f'{team_id}.{bundle_id}'
        self.rp_id_hash = hashlib.sha256(self.app_id.encode()).digest()
        self.environment = environment

    @property
    def configured(self) -> bool:
        return bool(self.app_id.strip('.'))

    def verify_attestation(self, key_id: bytes, attestation: bytes,
                           challenge: bytes) -> tuple[bytes, int]:
        """Первая встреча с устройством. Возвращает открытый ключ и счётчик."""
        obj = cbor2.loads(attestation)
        if obj.get('fmt') != 'apple-appattest':
            raise AttestError(f'чужой формат заверения: {obj.get("fmt")}')
        stmt = obj['attStmt']
        auth_data = obj['authData']

        # 1–2. Цепочка сертификатов до корня Apple.
        chain = [x509.load_der_x509_certificate(c) for c in stmt['x5c']]
        if not chain:
            raise AttestError('в заверении нет сертификатов')
        _verify_chain(chain)

        # 3–4. Нонс: он же челлендж, пропущенный через authData.
        client_data_hash = hashlib.sha256(challenge).digest()
        expected = hashlib.sha256(auth_data + client_data_hash).digest()
        ext = chain[0].extensions.get_extension_for_oid(NONCE_OID)
        if _der_walk(ext.value.value) != expected:
            raise AttestError('нонс не совпал — челлендж чужой или подменён')

        parsed = _parse_auth_data(auth_data, with_credential=True)

        # 5. keyId — это отпечаток открытого ключа, и он же лежит в authData.
        public_key = _public_key_bytes(parsed['cose_key'])
        cert_key = chain[0].public_key().public_bytes(
            encoding=serialization.Encoding.X962,
            format=serialization.PublicFormat.UncompressedPoint)
        if cert_key != public_key:
            raise AttestError('ключ в сертификате и в authData разные')
        digest = hashlib.sha256(public_key).digest()
        if digest != key_id or parsed['credential_id'] != key_id:
            raise AttestError('keyId не совпадает с отпечатком ключа')

        # 6. Приложение — наше, счётчик у свежего ключа нулевой.
        if parsed['rp_id_hash'] != self.rp_id_hash:
            raise AttestError('заверение выдано другому приложению')
        allowed = {AAGUID_PROD} if self.environment == 'production' else {
            AAGUID_PROD, AAGUID_DEV}
        if parsed['aaguid'] not in allowed:
            raise AttestError(
                f'сборка не из той среды: {parsed["aaguid"]!r}')
        if parsed['counter'] != 0:
            raise AttestError('счётчик свежего ключа не ноль')

        return public_key, parsed['counter']

    def verify_assertion(self, public_key: bytes, assertion: bytes,
                         challenge: bytes, last_counter: int) -> int:
        """Каждый следующий заход. Возвращает новое значение счётчика."""
        obj = cbor2.loads(assertion)
        auth_data = obj['authenticatorData']
        signature = obj['signature']

        client_data_hash = hashlib.sha256(challenge).digest()
        nonce = hashlib.sha256(auth_data + client_data_hash).digest()

        # Тонкость, на которой спотыкаются все: устройство подписывает не сам
        # нонс, а его хеш — по существу SHA256(SHA256(authData||clientDataHash)).
        # Поэтому нонс идёт в проверку как сообщение, а не как готовый дайджест.
        key = _load_key(public_key)
        try:
            key.verify(signature, nonce, ec.ECDSA(hashes.SHA256()))
        except InvalidSignature:
            # Второе прочтение той же документации: нонс как готовый дайджест.
            # Держим запасным, чтобы разница в трактовке не выглядела как
            # поломка приложения, но говорим о ней в журнале громко.
            try:
                key.verify(signature, nonce, ec.ECDSA(Prehashed(hashes.SHA256())))
                log.warning('подпись сошлась только по запасному прочтению '
                            'нонса — проверьте verify_assertion')
            except InvalidSignature as e:
                raise AttestError('подпись не сошлась') from e

        parsed = _parse_auth_data(auth_data, with_credential=False)
        if parsed['rp_id_hash'] != self.rp_id_hash:
            raise AttestError('подпись выдана другому приложению')
        # Счётчик у Apple только растёт. Если он не вырос — это повтор чужой
        # записанной подписи, а не новый запрос.
        if parsed['counter'] <= last_counter:
            raise AttestError('счётчик не вырос — повтор старой подписи')
        return parsed['counter']
