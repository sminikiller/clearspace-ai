import Foundation

/// Struttura "union-find" per raggruppare elementi collegati a coppie.
struct DisjointSet {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0..<max(0, count))
    }

    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root {
            root = parent[root]
        }
        var current = element
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ first: Int, _ second: Int) {
        let firstRoot = find(first)
        let secondRoot = find(second)
        if firstRoot != secondRoot {
            parent[firstRoot] = secondRoot
        }
    }

    /// Gruppi di indici collegati tra loro (compresi quelli formati da un solo elemento).
    mutating func groups() -> [[Int]] {
        var result: [Int: [Int]] = [:]
        for index in parent.indices {
            result[find(index), default: []].append(index)
        }
        return Array(result.values)
    }
}
