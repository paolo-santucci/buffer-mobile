package com.paolosantucci.foglietto.shared

import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class JvmSmokeTest {

    @Test
    fun jvmIdentityResolvable() {
        // Asserts that this test is running on a real JVM (not a stub environment).
        val vmName = System.getProperty("java.vm.name")
        assertNotNull(vmName, "java.vm.name system property must be present on the JVM target")
        assertTrue(vmName.isNotBlank(), "java.vm.name must not be blank")
    }

    @Test
    fun greetingContainsFoglietto() {
        val greeting = SharedPlaceholder.greeting()
        assertTrue(
            greeting.contains("Foglietto"),
            "SharedPlaceholder.greeting() must contain 'Foglietto'; got: $greeting"
        )
    }
}
