// macOS Vision으로 명함 사진에서 글자를 읽어 **측정 형식 v3**로 찍는다.
//
// ## 왜 있나 (추가 405·409)
//
// 파서를 고칠 때 "전체적으로 좋아졌는가"를 알려면 명함별 대조가 있어야 하는데,
// 앱은 명함별 OCR 원문을 저장하지 않는다. 기기로 재려면 빌드→설치→스캔에
// 수십 분이 든다. 이 도구는 **맥에서 즉시** 같은 형식의 줄을 만들어 파서
// 테스트에 바로 먹일 수 있게 한다.
//
// ⚠️ **Vision은 ML Kit이 아니다.** 2026-08-22에 이 자로 84%를 봤는데 기기에서
// 실제로 재니 75%였다 — 줄 나눔이 달라 경로와 결과가 갈린다. **이 도구의
// 숫자는 방향을 보는 자이지 실적이 아니다.** 판정은 기기 측정으로 한다.
//
// ## 쓰는 법
//
//   swiftc -O tool/ocr_review/vision_measure.swift -o /tmp/vision_measure
//   /tmp/vision_measure 명함1.jpg 명함2.jpg … > measure_vision_v2.tsv
//
// ⚠️ **결과에는 제3자 개인정보가 그대로 담긴다**(이름·전화·이메일·주소).
// 저장은 `connection-sense-assets/명함데이터/`(폴더 700) 규칙을 따르고,
// 저장소 안에 두지 않는다.
//
// ## 출력 형식 (앱의 `ocr_measure_dump.dart`와 같다)
//
//   사진이름 \t 줄칸 \t 경로 \t 뽑은이름 \t 토큰칸
//
//   줄칸    글자<0x02>높이<0x01>글자<0x02>높이 …
//   토큰칸  글자<0x02>높이<0x02>위<0x02>왼<0x02>너비<0x01>…   (v3)
//
// 경로·뽑은이름 두 칸은 **앱만 채울 수 있으므로 비운다**(파서를 태운 뒤 그 자리에
// 넣는다). 칸 수는 앱과 똑같이 다섯이라 같은 스크립트로 읽힌다.
//
// 높이·좌표는 **이미지 높이 대비 비율 × 1000**(정수)이다. 앱은 픽셀을 쓰지만
// 이 자는 상대 비교에만 쓰므로 비율이면 충분하고, 사진 크기가 제각각이어도
// 서로 견줄 수 있다.
import AppKit
import Foundation
import Vision

let LS = "\u{0001}"  // 줄 사이
let FS = "\u{0002}"  // 줄 안에서 칸 사이

for path in CommandLine.arguments.dropFirst() {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { continue }

    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.recognitionLanguages = ["ko-KR", "en-US"]
    req.usesLanguageCorrection = false

    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try? handler.perform([req])

    // Vision의 좌표계는 아래가 0이다. 위→아래로 읽으려면 maxY 내림차순.
    let obs = (req.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }

    // 세로 눈금: 이미지 높이 대비 비율 × 1000.
    func scaled(_ v: CGFloat) -> Int { Int((v * 1000).rounded()) }
    // 가로 눈금: **가로세로 비를 곱해** 세로와 같은 자로 만든다. 이렇게
    // 해야 "틈이 글자 높이의 몇 배인가"를 바로 견줄 수 있다.
    let aspect = CGFloat(cg.width) / CGFloat(cg.height)
    func scaledX(_ v: CGFloat) -> Int { Int((v * aspect * 1000).rounded()) }
    /// Vision 좌표(아래가 0)를 위에서 잰 값으로 뒤집는다 — 앱과 방향을 맞춘다.
    func topOf(_ box: CGRect) -> Int { scaled(1 - box.maxY) }

    var lineParts: [String] = []
    var tokenParts: [String] = []

    for o in obs {
        guard let cand = o.topCandidates(1).first else { continue }
        let text = cand.string
        lineParts.append("\(text)\(FS)\(scaled(o.boundingBox.height))")

        // ⚠️ 토큰 상자는 **줄 상자를 쪼갠 것이 아니라 Vision에게 다시 묻는
        // 것**이다. `boundingBox(for:)`는 그 글자 범위의 실제 상자를 준다.
        // 실패하면 그 낱말은 건너뛴다 — 줄 높이로 대신 채우면 "쟀다"와
        // "짐작했다"가 한 파일에서 섞인다.
        for range in text.split(separator: " ", omittingEmptySubsequences: true).compactMap({
            piece -> Range<String.Index>? in text.range(of: String(piece))
        }) {
            guard let box = try? cand.boundingBox(for: range) else { continue }
            let word = String(text[range])
            // ⚠️ 너비가 있어야 **낱말 사이 틈**을 잰다(추가 412).
            // 틈 = 다음 낱말의 왼쪽 − (이 낱말의 왼쪽 + 너비). v2에는 이 칸이
            // 없어 자간 넓은 이름과 별개 낱말을 못 갈랐다(추가 411).
            //
            // ⚠️ 가로는 **이미지 너비**로 재야 한다. 높이 쪽 눈금(× 1000)을
            // 그대로 쓰면 사진이 가로로 길 때 틈이 실제보다 좁아 보인다.
            tokenParts.append(
                "\(word)\(FS)\(scaled(box.boundingBox.height))"
                    + "\(FS)\(topOf(box.boundingBox))"
                    + "\(FS)\(scaledX(box.boundingBox.minX))"
                    + "\(FS)\(scaledX(box.boundingBox.width))")
        }
    }

    let name = (path as NSString).lastPathComponent
    // 3·4번 칸(경로·뽑은이름)은 앱만 채울 수 있어 비워 둔다.
    print("\(name)\t\(lineParts.joined(separator: LS))\t\t\t\(tokenParts.joined(separator: LS))")
}
