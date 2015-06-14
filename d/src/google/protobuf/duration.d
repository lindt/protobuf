module google.protobuf.duration;

import core.time : StdDuration = Duration;
import google.protobuf;

struct Duration
{
    private struct ProtobufMessage
    {
        @Proto(1) long seconds = defaultValue!(long);
        @Proto(2) int nanos = defaultValue!(int);
    }

    StdDuration duration;

    alias duration this;

    auto toProtobuf()
    {
        auto splitedDuration = duration.split!("seconds", "nsecs");
        auto protobufMessage = ProtobufMessage(splitedDuration.seconds, cast(int) splitedDuration.nsecs);

        return protobufMessage.toProtobuf;
    }

    Duration fromProtobuf(R)(ref R inputRange)
    {
        import core.time : dur;

        auto protobufMessage = inputRange.fromProtobuf!ProtobufMessage;
        duration = dur!"seconds"(protobufMessage.seconds) + dur!"nsecs"(protobufMessage.nanos);

        return this;
    }
}

unittest
{
    import std.algorithm.comparison : equal;
    import std.array : array;
    import std.datetime : msecs, seconds;

    assert(equal(Duration(5.seconds + 5.msecs).toProtobuf, [0x08, 0x05, 0x10, 0xc0, 0x96, 0xb1, 0x02]));
    assert(equal(Duration(5.msecs).toProtobuf, [0x10, 0xc0, 0x96, 0xb1, 0x02]));
    assert(equal(Duration((-5).msecs).toProtobuf, [0x10, 0xc0, 0xe9, 0xce, 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]));
    assert(equal(Duration((-5).seconds + (-5).msecs).toProtobuf, [
        0x08, 0xfb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
        0x10, 0xc0, 0xe9, 0xce, 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]));

    assert(equal(toProtobuf!(Proto(1))(Duration(5.msecs)), [0x10, 0xc0, 0x96, 0xb1, 0x02]));

    auto buffer = Duration(5.seconds + 5.msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Duration == Duration(5.seconds + 5.msecs));
    buffer = Duration(5.msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Duration == Duration(5.msecs));
    buffer = Duration((-5).msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Duration == Duration((-5).msecs));
    buffer = Duration((-5).seconds + (-5).msecs).toProtobuf.array;
    assert(buffer.fromProtobuf!Duration == Duration((-5).seconds + (-5).msecs));

    buffer = Duration(StdDuration.zero).toProtobuf.array;
    assert(buffer.empty);
    assert(buffer.fromProtobuf!Duration == Duration.zero);
}
