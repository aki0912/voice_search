//
//  VoiceSearchTests.swift
//  VoiceSearchTests
//
//  Created by akihiro on 2026/02/23.
//

import Testing

#if canImport(VoiceSearchApp)
@testable import VoiceSearchApp
#elseif canImport(VoiceSearch)
@testable import VoiceSearch
#else
#error("Neither VoiceSearchApp nor VoiceSearch module is available")
#endif

struct VoiceSearchTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}
