package com.paolosantucci.foglietto.shared

/**
 * Trivial placeholder proving the shared module compiles and giving the iosApp shell
 * a symbol to call as link-proof.
 *
 * M1 only — NO domain, recovery, settings, editor, or presentation logic.
 * That work begins in Milestone 2.
 */
object SharedPlaceholder {
    const val name: String = "foglietto-shared"

    fun greeting(): String = "Foglietto shared module $name"
}
