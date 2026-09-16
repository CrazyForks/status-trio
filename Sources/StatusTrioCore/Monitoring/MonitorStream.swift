enum MonitorStream {
    static func make<Element>(
        of type: Element.Type
    ) -> (AsyncStream<Element>, AsyncStream<Element>.Continuation) {
        AsyncStream.makeStream(
            of: type,
            bufferingPolicy: .bufferingNewest(1)
        )
    }
}
