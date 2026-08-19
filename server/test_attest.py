"""Проверки разбора App Attest.

Заверение (`verify_attestation`) целиком проверить здесь нельзя: цепочка
сертификатов подписана Apple, подделать её нарочно не выйдет — и хорошо.
Проверяется то, что можно: подпись очередного захода, защита от повтора старой
подписи и отказ чужому приложению.

Запуск: `.venv/bin/python test_attest.py`
"""

import hashlib
import struct
import sys

import cbor2
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

from attest import AppAttest, AttestError, _der_walk

TEAM, BUNDLE = 'VPJ76776P6', 'com.holybible.holyBible'


def make_assertion(key, app_id: str, challenge: bytes, counter: int) -> bytes:
    auth = hashlib.sha256(app_id.encode()).digest() + bytes([0]) + \
        struct.pack('>I', counter)
    nonce = hashlib.sha256(auth + hashlib.sha256(challenge).digest()).digest()
    sig = key.sign(nonce, ec.ECDSA(hashes.SHA256()))
    return cbor2.dumps({'signature': sig, 'authenticatorData': auth})


def run() -> None:
    a = AppAttest(TEAM, BUNDLE, 'production')
    key = ec.generate_private_key(ec.SECP256R1())
    pub = key.public_key().public_bytes(
        encoding=serialization.Encoding.X962,
        format=serialization.PublicFormat.UncompressedPoint)
    challenge = b'test-challenge'

    counter = a.verify_assertion(pub, make_assertion(key, a.app_id, challenge, 1),
                                 challenge, 0)
    assert counter == 1, counter
    print('подпись принимается, счётчик', counter)

    # Повтор той же подписи: счётчик не вырос — отказ.
    try:
        a.verify_assertion(pub, make_assertion(key, a.app_id, challenge, 1),
                           challenge, 1)
        raise SystemExit('ОШИБКА: повтор старой подписи прошёл')
    except AttestError as e:
        print('повтор отклонён:', e)

    # Подпись чужого приложения.
    try:
        a.verify_assertion(pub, make_assertion(key, 'XXXX.com.other', challenge, 5),
                           challenge, 0)
        raise SystemExit('ОШИБКА: чужое приложение прошло')
    except AttestError as e:
        print('чужое приложение отклонено:', e)

    # Челлендж, которого устройство не подписывало.
    try:
        a.verify_assertion(pub, make_assertion(key, a.app_id, challenge, 7),
                           b'other-challenge', 0)
        raise SystemExit('ОШИБКА: чужой челлендж прошёл')
    except AttestError as e:
        print('чужой челлендж отклонён:', e)

    # Разбор расширения с нонсом: SEQUENCE { [1] { OCTET STRING(32) } }.
    nonce = bytes(range(32))
    der = bytes([0x30, 0x24, 0xA1, 0x22, 0x04, 0x20]) + nonce
    assert _der_walk(der) == nonce
    print('нонс из расширения разбирается')

    print('\nвсе проверки прошли')


if __name__ == '__main__':
    sys.exit(run())
