package fixture

import std.deriving.*

@Derive[Equatable]
class Point {
    let x: Int64

    init(x: Int64) {
        this.x = x
    }
}
