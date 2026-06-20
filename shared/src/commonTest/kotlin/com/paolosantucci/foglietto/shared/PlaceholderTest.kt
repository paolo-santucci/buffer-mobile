package com.paolosantucci.foglietto.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PlaceholderTest {

    @Test
    fun triviallyTrue() {
        // Trivially-true baseline: the shared module compiles and commonTest runs.
        assertEquals(2, 1 + 1)
        assertTrue(true)
    }

    @Test
    fun placeholderNameIsCorrect() {
        assertEquals("foglietto-shared", SharedPlaceholder.name)
    }
}
