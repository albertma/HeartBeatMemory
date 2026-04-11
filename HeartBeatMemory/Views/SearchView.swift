import SwiftUI
import CoreData

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText: String = ""
    @State private var selectedMood: Mood?
    @State private var selectedCategory: Category?
    
    var filteredMemories: [HeartBeatMemory] {
        var result = appState.memories
        
        if !searchText.isEmpty {
            result = result.filter { memory in
                memory.title.contains(searchText) ||
                memory.summary.contains(searchText) ||
                memory.aiTags.contains { $0.contains(searchText) }
            }
        }
        
        if let mood = selectedMood {
            result = result.filter { $0.mood == mood }
        }
        
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        
        return result.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Mood.allCases, id: \.self) { mood in
                            FilterChip(title: mood.emoji, isSelected: selectedMood == mood) {
                                selectedMood = selectedMood == mood ? nil : mood
                            }
                        }
                        
                        Divider().frame(height: 24)
                        
                        ForEach(Category.allCases, id: \.self) { category in
                            FilterChip(title: category.rawValue, isSelected: selectedCategory == category) {
                                selectedCategory = selectedCategory == category ? nil : category
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.secondarySystemBackground))
                
                if filteredMemories.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(LocalizedStringKey("no_memory"))
                            .font(.headline)
                        Text(LocalizedStringKey("try_adjust_search"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredMemories) { memory in
                                MemoryCard(hbMemory: memory)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("search"))
            .searchable(text: $searchText, prompt: "搜索回忆...")
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.tertiarySystemFill))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

#Preview {
    SearchView()
        .environmentObject(AppState(viewContext: PersistenceController.preview.container.viewContext))
}
