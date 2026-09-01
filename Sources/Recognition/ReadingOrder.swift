import Foundation

/// Puts recognised text boxes into the order a person would read them.
///
/// Vision returns observations in *its* order, which for a two-column layout is
/// column-major: the whole left column, then the whole right one. That is right
/// for newspaper prose and wrong for almost everything a clipboard manager
/// actually sees — settings panes, tables, key/value dialogs — where it pairs
/// every label with the wrong value. Row-major is the better default for that
/// content, and single-column images, which are the majority, read identically
/// either way.
///
/// Pure geometry over rectangles rather than over `VNRecognizedTextObservation`,
/// so the rule that decides "these two boxes are on the same line" can be tested
/// against a layout written down by hand instead of against a screenshot.
enum ReadingOrder {

    /// Two boxes belong to the same row when their centres are closer than this
    /// fraction of the taller one's height.
    ///
    /// 0.6 rather than 0.5: text on one line is rarely aligned to the pixel —
    /// a bold label beside lighter value text, or a number beside a word with a
    /// descender, sit slightly differently — and a tolerance below half a line
    /// splits them into two rows.
    static let rowTolerance: CGFloat = 0.6

    /// Indices into `boxes`, in reading order.
    ///
    /// Boxes are in Vision's coordinate space: normalised, origin bottom-left, so
    /// a larger `midY` sits higher on the page.
    static func rowMajor(_ boxes: [CGRect]) -> [Int] {
        guard boxes.count > 1 else { return Array(boxes.indices) }

        let topDown = boxes.indices.sorted { boxes[$0].midY > boxes[$1].midY }

        var rows: [[Int]] = []
        for index in topDown {
            // Compared against the row's first box rather than its last: the
            // first is the one that established the row's baseline, and drifting
            // the reference along a wide row lets a run of slightly-offset boxes
            // walk the row down the page.
            if let reference = rows.last?.first {
                let tolerance = max(boxes[index].height, boxes[reference].height) * rowTolerance
                if abs(boxes[reference].midY - boxes[index].midY) < tolerance {
                    rows[rows.count - 1].append(index)
                    continue
                }
            }
            rows.append([index])
        }

        return rows.flatMap { row in row.sorted { boxes[$0].minX < boxes[$1].minX } }
    }
}
