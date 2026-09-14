package com.holybible.holy_bible

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityException
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import com.google.android.play.core.integrity.model.StandardIntegrityErrorCode
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Мост к Play Integrity — Android-аналог App Attest (ios/Runner/AppAttest.swift).
 *
 * Google Play выдаёт вердикт о подлинности приложения и устройства, привязанный
 * к челленджу сервера. Вердикт зашифрован — сюда он приходит непрозрачной
 * строкой и уходит на сервер как есть, расшифровывает его Google по запросу
 * сервера (server/play_integrity.py).
 *
 * Стандартный запрос: провайдер вердиктов готовится один раз — это медленно,
 * до секунд, — а сами вердикты потом выдаются быстро. Провайдер со временем
 * устаревает; тогда он сбрасывается и готовится заново при следующем запросе.
 */
class PlayIntegrityBridge(context: Context) {
    private val manager = IntegrityManagerFactory.createStandard(context)
    private var provider: StandardIntegrityTokenProvider? = null
    private var providerProject: Long? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "requestToken") {
            result.notImplemented()
            return
        }
        val project = call.argument<String>("cloudProjectNumber")?.toLongOrNull()
        val requestHash = call.argument<String>("requestHash")
        if (project == null || requestHash.isNullOrEmpty()) {
            result.error("bad_args", "Нужны cloudProjectNumber и requestHash", null)
            return
        }
        withProvider(project, result) { ready ->
            ready.request(
                StandardIntegrityTokenRequest.builder()
                    .setRequestHash(requestHash)
                    .build()
            )
                .addOnSuccessListener { response -> result.success(response.token()) }
                .addOnFailureListener { e ->
                    if (e is StandardIntegrityException &&
                        e.errorCode == StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID
                    ) {
                        provider = null
                    }
                    fail(result, e)
                }
        }
    }

    private fun withProvider(
        project: Long,
        result: MethodChannel.Result,
        block: (StandardIntegrityTokenProvider) -> Unit,
    ) {
        val ready = provider
        if (ready != null && providerProject == project) {
            block(ready)
            return
        }
        manager.prepareIntegrityToken(
            PrepareIntegrityTokenRequest.builder()
                .setCloudProjectNumber(project)
                .build()
        )
            .addOnSuccessListener { prepared ->
                provider = prepared
                providerProject = project
                block(prepared)
            }
            .addOnFailureListener { e -> fail(result, e) }
    }

    /** Код ошибки Google доходит до приложения: по нему видно, что чинить. */
    private fun fail(result: MethodChannel.Result, e: Exception) {
        val code = if (e is StandardIntegrityException) "integrity_${e.errorCode}" else "integrity_error"
        result.error(code, e.message, null)
    }

    companion object {
        const val CHANNEL = "holybible/play_integrity"
    }
}
