//
//  FunnyNameGenerator.swift
//  Codex Usage
//
//  Created by Codex Code on 2026-01-07.
//

import Foundation

struct FunnyNameGenerator {
    static let names = ["Main"]

    static func getRandomName(excluding usedNames: [String]) -> String {
        let available = names.filter { !usedNames.contains($0) }
        return available.randomElement() ?? "Main"
    }
}
