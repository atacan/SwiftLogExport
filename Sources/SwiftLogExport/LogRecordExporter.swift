//===----------------------------------------------------------------------===//
//
// The code is mostly taken from the Swift OTel project
//
// Copyright (c) 2024 the Swift OTel project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public protocol LogRecordExporter<T>: Sendable {
    associatedtype T: LogRecord

    /// Export the given batch of logs.
    ///
    /// - Parameter batch: A batch of logs to export.
    func export(_ batch: some Collection<T> & Sendable) async throws

    /// Force the log exporter to export any previously received logs as soon as possible.
    func forceFlush() async throws

    /// Shut down the log exporter.
    ///
    /// This method gives exporters a chance to wrap up existing work such as finishing in-flight exports while not allowing new ones anymore.
    /// Once this method returns, the exporter is to be considered shut down and further invocations of ``export(_:)``
    /// are expected to fail.
    func shutdown() async
}
