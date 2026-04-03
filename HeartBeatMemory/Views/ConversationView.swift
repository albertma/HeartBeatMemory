//
//  ConversationView.swift
//  
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import SwiftUI

/// Displays the chat conversation as a scrollable list of messages.
struct ConversationView: View {
    /// Array of messages to display in the conversation
    let messages: [Message]
    
    /// 外部传入的用于 dismiss keyboard 的 action
    var dismissKeyboard: (() -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(messages) { message in
                    MessageView(message)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 8)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .onTapGesture {
            dismissKeyboard?()
        }
    }
}

