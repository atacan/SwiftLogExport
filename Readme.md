# SwiftLogExport

A generic exporter and processor framework for `swift-log` backends.

This package provides the boilerplate for building robust `swift-log` backends. Simply integrate your specific exporting logic (e.g., calling a vendor API), and `SwiftLogExport` handles the complexities of buffering, non-blocking processing, and graceful shutdown.

## Features

-   **Generic:** Designed to be adaptable for various logging backends.
-   **Buffering:** Efficiently batches log entries before exporting.
-   **Non-blocking Processing:** Ensures your application remains responsive by handling log exporting asynchronously.
-   **Graceful Shutdown:** Handles in-flight log entries during application termination.

## Usage

To use `SwiftLogExport`, you need to implement the required protocols to provide your specific log exporting logic. The package takes care of managing the log processing pipeline.

Create a struct or class that conforms to `LogExporter`. You'll need to implement the `export(batch:)` method, which receives an array of `LogRecord`s.

`LogRecord` is a protocol that represents the log entry that matches your use case.

Then initialize a `LoggingHandler` with your `BatchLogRecordProcessor`, and use it to initialize a `Logger`.

Run the `BatchLogRecordProcessor` as it a `Service`.

### Examples

- [Logging to Telegram](https://github.com/atacan/TelegramBotAPI/tree/main/Sources/LoggingToTelegram)

## Installation

Add `SwiftLogExport` to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/atacan/SwiftLogExport.git", from: "1.0.0")
]
```

And add it to your target's dependencies:

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SwiftLogExport", package: "SwiftLogExport"),
        ]),
    // ... other targets
]
```

## Acknowledgements

- [swift-otel](https://github.com/swift-otel/swift-otel): The core processing and exporting logic is heavily adapted from the swift-otel project. See its [LICENSE](https://github.com/swift-otel/swift-otel/blob/main/LICENSE.txt) for more details.