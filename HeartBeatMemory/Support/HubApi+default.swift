//
//  HubApiExtension.swift
//  HeartBeatMemory
//
//  Created by albertma on 2026/3/30.
//

import Foundation
import Hub

/// Extension providing a default HubApi instance for downloading model files
enum HubApiExtension {
    #if os(macOS)
        static let `default` = HubApi(
            downloadBase: URL.downloadsDirectory.appending(path: "huggingface")
        )
    #else
        static let `default` = HubApi(
            downloadBase: URL.cachesDirectory.appending(path: "huggingface")
        )
    #endif
}