package com.mitransporte.mitransporte

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Clave del teléfono para el QR de MiRuta (docs/11 §11.8): par ECDSA P-256 en el
 * Android Keystore, que no se puede copiar ni exportar. Se crea la primera vez.
 */
object QrKey {
    private const val ALIAS = "miruta_qr_key"
    private const val PROVIDER = "AndroidKeyStore"

    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    @Synchronized
    private fun ensure(): KeyStore {
        val store = keyStore()
        if (!store.containsAlias(ALIAS)) {
            val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER)
            generator.initialize(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setUserAuthenticationRequired(false)
                    .build(),
            )
            generator.generateKeyPair()
        }
        return store
    }

    /** Clave pública en SPKI DER (X.509 SubjectPublicKeyInfo). */
    fun publicKey(): ByteArray = ensure().getCertificate(ALIAS).publicKey.encoded

    /** Firma SHA256withECDSA en DER. */
    fun sign(bytes: ByteArray): ByteArray {
        val key = ensure().getKey(ALIAS, null) as PrivateKey
        return Signature.getInstance("SHA256withECDSA").run {
            initSign(key)
            update(bytes)
            sign()
        }
    }
}
