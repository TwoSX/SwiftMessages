//
//  MessageGeometryProxy.swift
//  SwiftMessages
//
//  Created by Timothy Moose on 6/24/24.
//  Copyright © 2024 SwiftKick Mobile. All rights reserved.
//

import SwiftUI

/// A  data type that mimicks `GeomtryProxy` and is used with `swiftMessage()` modifier when the geomtry metrics of the container view
/// are needed, particularly because `GeometryReader` doesn't work inside the view builder due to the way the message view is being
/// displayed from UIKit.
public struct MessageGeometryProxy {
    /// 完整的容器尺寸（包括安全区域）
    public var fullSize: CGSize
    /// 减去安全区域后的尺寸（向后兼容）
    public var size: CGSize
    /// 安全区域的边距
    public var safeAreaInsets: EdgeInsets
}
