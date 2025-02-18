//
//  Shape+mLayout.swift
//  
//
//  Created by Nail Sharipov on 02.06.2023.
//

import iFixFloat
import iShape

enum MLayoutStatus {
    case empty
    case success
    case fail
}

struct MLayout {
    static let fail = MLayout(startList: [], navNodes: [], sliceList: [], status: .fail)
    static let empty = MLayout(startList: [], navNodes: [], sliceList: [], status: .empty)
    
    let startList: [Int]
    let navNodes: [MNavNode]
    let sliceList: [MSlice]
    let status: MLayoutStatus
}

extension Shape {

    var mLayout: MLayout {
        let nLayout = self.nLayout

        guard !nLayout.specNodes.isEmpty else {
            return .empty
        }
        
        let first = nLayout.specNodes[0]
        guard first.type == .start else {
            return .empty
        }
        
        var startList = [Int]()
        startList.append(first.index)

        var specs = nLayout.specNodes
        var navs = nLayout.navNodes
        
        var sliceList = [MSlice]()
        var mPolies = [MPoly]()
        
        mPolies.append(MPoly(start: navs[first.index].index))

        var j = 1
        
        while j < specs.count && !mPolies.isEmpty {
            let spec = specs[j]

            let px = Self.fill(mPolies: &mPolies, verts: navs, stop: spec.sort, stopIndex: spec.index)

            let nav = navs[spec.index]
            
            switch spec.type {
            case .end:
                guard px.next == px.prev && px.next != .empty else { return .fail }
                let pIndex = px.next
                mPolies.remove(at: pIndex)
            case .start:
                startList.append(spec.index)
                mPolies.append(MPoly(start: nav.index))
            case .split:
                var pIndex: Int = .empty
                for i in 0..<mPolies.count {
                    if Self.isContain(mPoly: mPolies[i], point: nav.vert.point, navs: navs) {
                        pIndex = i
                        break
                    }
                }
                guard pIndex != .empty else { return .fail }
                
                let mPoly = mPolies[pIndex]

                let sv = nav
                
                if mPoly.next == mPoly.prev {
                    let start = mPoly.next
                    let s = navs.newNext(a: start, b: sv.index)
                    sliceList.append(s.slice)
                    
                    mPolies[pIndex] = MPoly(next: start, prev: sv.index)
                    mPolies.append(MPoly(next: s.b.index, prev: s.a.index))
                    
                    startList.append(s.a.index)
                } else {
                    let a = navs[mPoly.next].vert.point
                    let b = navs[mPoly.prev].vert.point
                    
                    let sp = nav.vert.point
                    
                    let isNext = a.x == b.x ? sp.sqrDistance(a) < sp.sqrDistance(b) : a.x > b.x
                    
                    if isNext {
                        let nv = mPoly.next
                        
                        let s = navs.newNext(a: sv.index, b: nv)
                        sliceList.append(s.slice)
                        
                        mPolies[pIndex] = MPoly(start: s.b.index)
                        startList.append(s.b.index)

                        mPolies.append(MPoly(next: nv, prev: mPoly.prev))
                    } else {
                        let nv = mPoly.prev
      
                        let s = navs.newNext(a: nv, b: sv.index)
                        sliceList.append(s.slice)
                        
                        // next
                        mPolies[pIndex] = MPoly(next: mPoly.next, prev: sv.index)
                        
                        // prev
                        mPolies.append(MPoly(next: s.b.index, prev: s.a.index))

                        startList.append(s.a.index)
                    }
                }
            case .merge:
                guard px.next != .empty && px.prev != .empty else {
                    return .fail
                }
                
                let nextPoly = mPolies[px.next]
                let prevPoly = mPolies[px.prev]
                
                let prev = navs[prevPoly.prev]
                let next = navs[nextPoly.next]

                let ms = Self.findNodeToMerge(prev: prev, next: next, merge: nav, startNode: j + 1, specs: specs, navs: navs)
                
                switch ms.type {
                case .direct:
                    let rNode = specs.remove(at: ms.nodeIndex)

                    let s = navs.newNext(a: ms.a, b: ms.b)
                    sliceList.append(s.slice)

                    if rNode.type == .end {
                        if px.next > px.prev {
                            mPolies.remove(at: px.next)
                            mPolies.remove(at: px.prev)
                        } else {
                            mPolies.remove(at: px.prev)
                            mPolies.remove(at: px.next)
                        }
                    } else {
                        mPolies[px.next] = MPoly(
                            next: nextPoly.next,
                            prev: ms.b
                        )
                        
                        mPolies[px.prev] = MPoly(
                            next: s.b.index,
                            prev: prevPoly.prev
                        )
                    }
                case .next:
                    let s = navs.newNext(a: ms.b, b: ms.a)
                    sliceList.append(s.slice)
                    mPolies.remove(at: px.next)
                case .prev:
                    let s = navs.newNext(a: ms.a, b: ms.b)
                    sliceList.append(s.slice)
                    mPolies.remove(at: px.prev)
                }
            }
            
            j += 1
        } // while

        guard j == specs.count else {
            return .fail
        }

#if DEBUG
        for start in startList {
            assert(!navs.isEmpty(start: start))
            assert(start == navs.findStart(index: start))
        }
#endif

        return MLayout(startList: startList, navNodes: navs, sliceList: sliceList, status: .success)
    }

    private struct NavIndex {
        let next: Int
        let prev: Int
    }

    // update next and prev ends of all polies and find index of next and prev polies if present
    private static func fill(mPolies: inout [MPoly], verts: [MNavNode], stop: BitPack, stopIndex: Int) -> NavIndex {
        var nextPolyIx: Int = .empty
        var prevPolyIx: Int = .empty
        for i in 0..<mPolies.count {
            var mPoly = mPolies[i]
            
            var n0 = verts[mPoly.next]
            var n1 = verts[n0.next]

            while n1.vert.point.bitPack < stop  {
                n0 = n1
                n1 = verts[n1.next]
            }

            if n1.vert.index == stopIndex {
                mPoly.next = n1.index
                prevPolyIx = i
            } else {
                mPoly.next = n0.index
            }
            
            var p0 = verts[mPoly.prev]
            var p1 = verts[p0.prev]

            while p1.vert.point.bitPack < stop {
                p0 = p1
                p1 = verts[p1.prev]
            }
            
            if p1.vert.index == stopIndex {
                mPoly.prev = p1.index
                nextPolyIx = i
            } else {
                mPoly.prev = p0.index
            }
            
            mPolies[i] = mPoly
        }
        
        return NavIndex(next: nextPolyIx, prev: prevPolyIx)
    }
    
    private enum MType {
        case direct
        case next
        case prev
    }
    
    private struct MSolution {
        let type: MType
        let a: Int
        let b: Int
        let nodeIndex: Int
    }

    private static func findNodeToMerge(prev: MNavNode, next: MNavNode, merge: MNavNode, startNode: Int, specs: [MSpecialNode], navs: [MNavNode]) -> MSolution {
        let a0 = next.vert.point
        let va1 = navs[next.next].vert
        let vb1 = navs[prev.prev].vert
        let b0 = prev.vert.point

        let m = merge.vert.point

        // check inner nodes
        if startNode < specs.count {
            
            // 3 triangles:
            // top: m, a0, a1
            // middle: m, a1, b1
            // bottom: m, b1, b0

            let minX = Swift.min(va1.point.x, vb1.point.x)
            
            var i = startNode
            
            while i < specs.count {
                let spec = specs[i]
                let nav = navs[spec.index]
                let v = nav.vert
                if v.point.x > minX {
                    break
                }
                if spec.type == .split || spec.type == .end {
                    // if it end it can be unreachable (same point for different vertices!)
                    let isBadEnd = v.point == va1.point && v.index != va1.index || v.point == vb1.point && v.index != vb1.index
                    if !isBadEnd {
                        let m_a0_a1 = Triangle.isContain_eclude_borders(p: v.point, p0: m, p1: a0, p2: va1.point)
                        let m_a1_b1 = Triangle.isContain(p: v.point, p0: m, p1: va1.point, p2: vb1.point)
                        let m_b1_b0 = Triangle.isContain_eclude_borders(p: v.point, p0: m, p1: vb1.point, p2: b0)
                        let isContain = m_a0_a1 || m_a1_b1 || m_b1_b0
                        if isContain {
                            return MSolution(type: .direct, a: merge.index, b: nav.index, nodeIndex: i)
                        }
                    }
                }
                i += 1
            }
        }
        
        let compare = va1.point.x == vb1.point.x ? m.sqrDistance(va1.point) < m.sqrDistance(vb1.point) : va1.point.x < vb1.point.x
        
        if compare {
            return MSolution(type: .next, a: merge.index, b: next.next, nodeIndex: .empty)
        } else {
            return MSolution(type: .prev, a: merge.index, b: prev.prev, nodeIndex: .empty)
        }
    }
    
    private static func isContain(mPoly: MPoly, point: Point, navs: [MNavNode]) -> Bool {
        let a0 = navs[mPoly.next]
        let a1 = navs[a0.next]
        
        let b0 = navs[mPoly.prev]
        let b1 = navs[b0.prev]

        return isContain(point: point, a0: a0.vert.point, a1: a1.vert.point, b0: b0.vert.point, b1: b1.vert.point)
    }
    
    private static func isContain(point p: Point, a0: Point, a1: Point, b0: Point, b1: Point) -> Bool {
        let is_first = Triangle.isContain(p: p, p0: a0, p1: a1, p2: b0) && Triangle.unsafeAreaTwo(p0: a0, p1: a1, p2: b0) != 0
        let is_second = Triangle.isContain(p: p, p0: b0, p1: b1, p2: a1) && Triangle.unsafeAreaTwo(p0: b0, p1: b1, p2: a1) != 0
        
        return is_first || is_second
    }
}
