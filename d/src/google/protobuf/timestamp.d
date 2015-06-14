module google.protobuf.timestamp;

import std.datetime : SysTime, unixTimeToStdTime;
import google.protobuf;

struct Timestamp
{
    private struct ProtobufMessage
    {
      @Proto(1) long seconds = defaultValue!(long);
      @Proto(2) int nanos = defaultValue!(int);
    }

    SysTime timestamp;

    alias timestamp this;

    auto toProtobuf()
    {
        long epochDelta = timestamp.stdTime - unixTimeToStdTime(0);
        auto protobufMessage = ProtobufMessage(epochDelta / 1_000_000_0, epochDelta % 1_000_000_0 * 100);

        return protobufMessage.toProtobuf;
    }

    Timestamp fromProtobuf(R)(ref R inputRange)
    {
        auto protobufMessage = inputRange.fromProtobuf!ProtobufMessage;
        long epochDelta = protobufMessage.seconds * 1_000_000_0 + protobufMessage.nanos / 100;
        timestamp.stdTime = epochDelta + unixTimeToStdTime(0);

        return this;
    }
}

unittest
{
    import std.algorithm.comparison : equal;
    import std.array : array;
    import std.datetime : DateTime, msecs, seconds, UTC;

    enum epoch = SysTime(DateTime(1970, 1, 1), UTC());

    //import std.stdio; writeln(Timestamp(epoch + 5.seconds + 5.msecs).toProtobuf);
    assert(equal(Timestamp(epoch + 5.seconds + 5.msecs).toProtobuf, [
        0x08, 0x05, 0x10, 0xc0, 0x96, 0xb1, 0x02]));
    assert(equal(Timestamp(epoch + 5.msecs).toProtobuf, [
        0x10, 0xc0, 0x96, 0xb1, 0x02]));
    assert(equal(Timestamp(epoch + (-5).msecs).toProtobuf, [
        0x10, 0xc0, 0xe9, 0xce, 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]));
    assert(equal(Timestamp(epoch + (-5).seconds + (-5).msecs).toProtobuf, [
        0x08, 0xfb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
        0x10, 0xc0, 0xe9, 0xce, 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]));

    auto buffer = Timestamp(epoch + 5.seconds + 5.msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Timestamp == Timestamp(epoch + 5.seconds + 5.msecs));
    buffer = Timestamp(epoch + 5.msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Timestamp == Timestamp(epoch + 5.msecs));
    buffer = Timestamp(epoch + (-5).msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Timestamp == Timestamp(epoch + (-5).msecs));
    buffer = Timestamp(epoch + (-5).seconds + (-5).msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Timestamp == Timestamp(epoch + (-5).seconds + (-5).msecs));

    buffer = Timestamp(epoch).toProtobuf.array;
    assert(buffer.empty);
    assert(buffer.fromProtobuf!Timestamp == epoch);
}
