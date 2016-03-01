module google.protobuf;

import std.algorithm : map;
import std.exception : enforce;
import std.range : chain, dropExactly, ElementType, empty, hasLength, InputRange, InputRangeObject, isInputRange, take;
import std.traits : isAggregateType, isArray, isAssociativeArray, isBoolean, isFloatingPoint, isIntegral, KeyType,
    ReturnType, ValueType;
import std.typecons : Flag, No, Yes;

alias bytes = ubyte[];

enum WireType : ubyte
{
    varint = 0,
    bits64 = 1,
    withLength = 2,
    bits32 = 5,
}

struct Proto
{
    uint tag;
    string wire;
    Flag!"packed" packed;
}

static struct Message(T)
{
    import std.meta : AliasSeq, Filter, staticMap, templateNot;

    alias fields = staticMap!(getField, sortedTaggedFields);
    alias protos = staticMap!(getProtoByField, fields);

    private alias unsortedFields = Filter!(isProtoField, __traits(allMembers, T));
    private alias unsortedTaggedFields = staticMap!(taggedField, unsortedFields);
    private alias sortedTaggedFields = Sorted!unsortedTaggedFields;

    template isProtoField(alias field)
    {
        import std.traits : hasUDA;

        static if (field != "this" &&
            __traits(getProtection, mixin("T." ~ field)) == "public")
        {
            enum isProtoField = hasUDA!(mixin("T." ~ field), Proto);
        }
        else
        {
            enum isProtoField = false;
        }
    }

    private struct TaggedField
    {
        const uint tag;
        string name;
    }

    private enum taggedField(string name) = TaggedField(getProtoByField!name.tag, name);

    template Sorted(T...)
    {
        static if (T.length <= 1)
        {
            alias Sorted = T;
        }
        else
        {
            enum Pivot = T[0];
            enum LessThanPivot(TaggedField F) = F.tag < Pivot.tag;
            enum Sorted = AliasSeq!(
                Sorted!(Filter!(LessThanPivot, T[1 .. $])),
                Pivot,
                Sorted!(Filter!(templateNot!LessThanPivot, T[1 .. $])));
        }
    }

    private enum getField(TaggedField T) = T.name;

    template getProtoByField(alias field)
    {
        import std.traits : getUDAs;

        enum getProtoByField = getUDAs!(mixin("T." ~ field), Proto)[0];
    }

    static assert(validate);
    static assert(fields.length > 0, "Definition of '" ~ T.stringof ~ "' has no Proto field");

    private static bool validate()
    {
        foreach (field; fields)
            validateProto!(getProtoByField!field, typeof(mixin("T." ~ field)));
        return true;
    }
}

unittest
{
    import std.typecons : tuple;

    static class Test
    {
        @Proto(3) int foo;
        @Proto(2, "fixed") int bar;
    }

    assert(tuple(Message!Test.fields) == tuple("bar", "foo"));
    assert(tuple(Message!Test.protos) == tuple(Proto(2, "fixed", No.packed), Proto(3, "", No.packed)));
}

auto toProtobufVarint(long value)
{
    struct Result
    {
        private long value;
        private ubyte index;
        private ubyte _length;

        this(long value)
        out { assert(_length > 0); }
        body
        {
            size_t encodingLength(long value)
            {
                import core.bitop : bsr;

                if (value == 0)
                    return 1;

                static if (long.sizeof <= size_t.sizeof)
                {
                    return bsr(value) / 7 + 1;
                }
                else
                {
                    if (value > 0 && value <= size_t.max)
                        return bsr(value) / 7 + 1;

                    enum bsrShift = size_t.sizeof * 8;
                    return (bsr(value >>> bsrShift) + bsrShift) / 7 + 1;
                }
            }

            this.value = value;
            this._length = cast(ubyte) encodingLength(value);
        }

        @property bool empty() { return index >= _length; }
        @property ubyte front() { return opIndex(index); }
        void popFront() { ++index; }

        ubyte opIndex(size_t index)
        in { assert(index < _length); }
        body
        {
            auto result = value >>> (index * 7);

            if (result >>> 7)
                return result & 0x7F | 0x80;
            else
                return result & 0x7F;
        }

        @property size_t length()
        in { assert(index <= _length); }
        body
        {
            return _length - index;
        }
    }

    return Result(value);
}

unittest
{
    import std.array : array;

    assert(toProtobufVarint(0).array == [0x00]);
    assert(toProtobufVarint(1).array == [0x01]);
    assert(toProtobufVarint(-1).array == [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]);
    assert(toProtobufVarint(-1L).array == [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]);
    assert(toProtobufVarint(int.max).array == [0xff, 0xff, 0xff, 0xff, 0x07]);
    assert(toProtobufVarint(int.min).array == [0x80, 0x80, 0x80, 0x80, 0xf8, 0xff, 0xff, 0xff, 0xff, 0x01]);
    assert(toProtobufVarint(long.max).array == [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f]);
    assert(toProtobufVarint(long.min).array == [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01]);
}

T zigZag(T)(T value)
if (is(T == int) || is(T == long))
{
    return (value << 1) ^ (value >> (T.sizeof * 8 - 1));
}

unittest
{
    assert(zigZag(0) == 0);
    assert(zigZag(-1) == 1);
    assert(zigZag(1L) == 2L);
    assert(zigZag(int.max) == 0xffff_fffe);
    assert(zigZag(int.min) == 0xffff_ffff);
    assert(zigZag(long.max) == 0xffff_ffff_ffff_fffe);
    assert(zigZag(long.min) == 0xffff_ffff_ffff_ffff);
}

auto toProtobuf(Proto proto = Proto(1), T)(T value)
if (isBoolean!T || isIntegral!T || isFloatingPoint!T)
{
    validateProto!(proto, T);

    static if (proto.wire == "fixed" || isFloatingPoint!T)
    {
        import std.bitmanip : nativeToLittleEndian;

        return nativeToLittleEndian(value).dup;
    }
    else static if (proto.wire == "zigzag")
    {
        return toProtobufVarint(zigZag(value));
    }
    else
    {
        return toProtobufVarint(value);
    }
}

unittest
{
    import std.array : array;

    assert(true.toProtobuf.array == [0x01]);
    assert(false.toProtobuf.array == [0x00]);
    assert(10.toProtobuf.array == [0x0a]);
    assert((-1).toProtobuf.array == [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]);
    assert((-1L).toProtobuf.array == [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]);
    assert(0xffffffffffffffffUL.toProtobuf.array == [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]);

    assert(1L.toProtobuf!(Proto(1, "fixed")).array == [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    assert((0.0).toProtobuf.array == [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);

    assert(1.toProtobuf!(Proto(1, "fixed")).array == [0x01, 0x00, 0x00, 0x00]);
    assert((-1).toProtobuf!(Proto(1, "fixed")).array == [0xff, 0xff, 0xff, 0xff]);
    assert(0xffffffffU.toProtobuf!(Proto(1, "fixed")).array == [0xff, 0xff, 0xff, 0xff]);
    assert((0.0f).toProtobuf.array == [0x00, 0x00, 0x00, 0x00]);

    assert(1.toProtobuf!(Proto(1, "zigzag")).array == [0x02]);
    assert((-1).toProtobuf!(Proto(1, "zigzag")).array == [0x01]);
    assert(1L.toProtobuf!(Proto(1, "zigzag")).array == [0x02]);
    assert((-1L).toProtobuf!(Proto(1, "zigzag")).array == [0x01]);
}

auto toProtobuf(Proto proto = Proto(1), T)(T value)
if (is(T == string) || is(T == bytes))
{
    validateProto!(proto, T);

    return chain(toProtobufVarint(value.length), cast(ubyte[]) value);
}

unittest
{
    import std.array : array;

    assert("abc".toProtobuf.array == [0x03, 'a', 'b', 'c']);
    assert("".toProtobuf.array == [0x00]);
    assert((cast(bytes) [1, 2, 3]).toProtobuf.array == [0x03, 1, 2, 3]);
    assert((cast(bytes) []).toProtobuf.array == [0x00]);
}

auto toProtobuf(Proto proto = Proto(1), T)(T value)
if (isArray!T && !is(T == string) && !is(T == bytes))
{
    static assert(proto.packed, "Non-packed repeated fields have no bulk encoding");
    validateProto!(proto, T);
    static assert(hasLength!T, "Cannot encode array with unknown length");

    enum elementProto = Proto(proto.tag, proto.wire);
    auto result = value.map!(a => a.toProtobuf!elementProto).joiner;

    return chain(toProtobufVarint(result.length), result);
}

unittest
{
    import std.array : array;

    assert([false, false, true].toProtobuf!(Proto(1, "", Yes.packed)).array == [0x03, 0x00, 0x00, 0x01]);
    assert([1, 2].toProtobuf!(Proto(1, "fixed", Yes.packed)).array ==
        [0x08, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00]);
    assert([1, 2].toProtobuf!(Proto(1, "", Yes.packed)).array == [0x02, 0x01, 0x02]);
}

auto toProtobuf(Proto proto = Proto(1), T)(T value)
if (isAssociativeArray!T)
{
    static assert(0, "The maps have no bulk encoding");
}

auto toProtobuf(Proto proto = Proto(1), T)(T value)
if (isAggregateType!T)
{
    import std.algorithm : stdJoiner = joiner;
    import std.array : array;
    import std.traits : hasMember;

    validateProto!(proto, T);

    static if (hasMember!(T, "toProtobuf"))
    {
        return value.toProtobuf;
    }
    else
    {
        enum fieldExpressions = [Message!T.fields]
            .map!(a => "value." ~ a ~ ".toProtobufTagged!(Message!T.getProtoByField!\"" ~ a ~ "\")")
            .stdJoiner(", ")
            .array;

        static if (is(T == class))
        {
            if (value is null)
                return typeof(mixin("chain(" ~ fieldExpressions ~ ")")).init;
        }
        return mixin("chain(" ~ fieldExpressions ~ ")");
    }
}

unittest
{
    import std.array : array;

    static class Foo
    {
        @Proto(1) int bar = defaultValue!int;
        @Proto(3) bool qux = defaultValue!bool;
        @Proto(2, "fixed") long baz = defaultValue!long;
        @Proto(4) string quux = defaultValue!string;
    }

    auto foo = new Foo;
    assert(foo.toProtobuf.empty);
    foo.bar = 5;
    foo.baz = 1;
    foo.qux = true;
    assert(foo.toProtobuf.array == [0x08, 0x05, 0x11, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x01]);
}

auto toProtobufTagged(Proto proto, Flag!"omitDefaultValues" omitDefaultValues = Yes.omitDefaultValues, T)(T value)
if (isArray!T && !proto.packed && !is(T == string) && !is(T == bytes) && !isAggregateType!(ElementType!T))
{
    validateProto!(proto, T);

    enum elementProto = Proto(proto.tag, proto.wire);
    return value.map!(a => a.toProtobufTagged!(elementProto, No.omitDefaultValues)).joiner;
}

SizedRange!ubyte toProtobufTagged(Proto proto, Flag!"omitDefaultValues" omitDefaultValues = Yes.omitDefaultValues, T)
    (T value)
if (isArray!T && !proto.packed && !is(T == string) && !is(T == bytes) && isAggregateType!(ElementType!T))
{
    validateProto!(proto, T);

    enum elementProto = Proto(proto.tag, proto.wire);
    return value
        .map!(a => a.toProtobufTagged!(elementProto, No.omitDefaultValues))
        .joiner
        .sizedRangeObject;
}

auto toProtobufTagged(Proto proto, Flag!"omitDefaultValues" omitDefaultValues = Yes.omitDefaultValues, T)(T value)
if (isAssociativeArray!T && !isAggregateType!(ValueType!T))
{
    import std.algorithm : findSplit;

    validateProto!(proto, T);

    enum wires = proto.wire.findSplit(",");
    enum keyProto = Proto(1, wires[0]);
    enum valueProto = Proto(2, wires[2]);

    return value.byKeyValue
        .map!(a => chain(a.key.toProtobufTagged!(keyProto, No.omitDefaultValues),
            a.value.toProtobufTagged!(valueProto, No.omitDefaultValues)))
        .map!(a => chain(toProtobufTag!(proto, T), toProtobufVarint(a.length), a))
        .joiner;
}

SizedRange!ubyte toProtobufTagged(Proto proto, Flag!"omitDefaultValues" omitDefaultValues = Yes.omitDefaultValues, T)
    (T value)
if (isAssociativeArray!T && isAggregateType!(ValueType!T))
{
    import std.algorithm : findSplit;

    validateProto!(proto, T);

    enum wires = proto.wire.findSplit(",");
    enum keyProto = Proto(1, wires[0]);
    enum valueProto = Proto(2, wires[2]);

    return value.byKeyValue
        .map!(a => chain(a.key.toProtobufTagged!keyProto, a.value.toProtobufTagged!valueProto))
        .map!(a => chain(toProtobufTag!(proto, T), a.length.toProtobufVarint, a))
        .joiner
        .sizedRangeObject;
}

SizedRange!ubyte toProtobufTagged(Proto proto, Flag!"omitDefaultValues" omitDefaultValues = Yes.omitDefaultValues, T)
    (T value)
if (isAggregateType!T)
{
    validateProto!(proto, T);

    static if (omitDefaultValues)
    {
        if (value == defaultValue!T)
            return sizedRangeObject(cast(ubyte[]) null);
    }

    auto result = toProtobuf!proto(value);
    return chain(toProtobufTag!(proto, T), result.length.toProtobufVarint, result).sizedRangeObject;
}

auto toProtobufTagged(Proto proto, Flag!"omitDefaultValues" omitDefaultValues = Yes.omitDefaultValues, T)(T value)
if (isBoolean!T || isIntegral!T || isFloatingPoint!T || is(T == string) || is(T == bytes) ||
    (isArray!T && proto.packed))
{
    validateProto!(proto, T);

    static if (omitDefaultValues)
    {
        if (value == defaultValue!T)
            return typeof(chain(toProtobufTag!(proto, T), toProtobuf!proto(value))).init;
    }

    return chain(toProtobufTag!(proto, T), toProtobuf!proto(value));
}

unittest
{
    import std.array : array;

    assert(0.toProtobufTagged!(Proto(1), No.omitDefaultValues).array == [0x08, 0x00]);
    assert(10.toProtobufTagged!(Proto(1)).array == [0x08, 0x0a]);
    assert(10.toProtobufTagged!(Proto(16)).array == [0x80, 0x01, 0x0a]);
    assert(true.toProtobufTagged!(Proto(2048)).array == [0x80, 0x80, 0x01, 0x01]);
    assert(true.toProtobufTagged!(Proto(262144)).array == [0x80, 0x80, 0x80, 0x01, 0x01]);

    assert(false.toProtobufTagged!(Proto(1)).empty);
    assert(0.toProtobufTagged!(Proto(1)).empty);
    assert(0.toProtobufTagged!(Proto(1, "fixed")).empty);
    assert(0.toProtobufTagged!(Proto(1, "zigzag")).empty);
    assert(0L.toProtobufTagged!(Proto(1)).empty);
    assert((0.0).toProtobufTagged!(Proto(1)).empty);
    assert("".toProtobufTagged!(Proto(1)).empty);
    assert((cast(bytes) []).toProtobufTagged!(Proto(1)).empty);

    assert([1, 2].toProtobufTagged!(Proto(1)).array == [0x08, 0x01, 0x08, 0x02]);
    assert([1, 2][0..0].toProtobufTagged!(Proto(1)).empty);
    assert([1, 2].toProtobufTagged!(Proto(1, "", Yes.packed)).array == [0x0a, 0x02, 0x01, 0x02]);
    assert([128, 2].toProtobufTagged!(Proto(1, "", Yes.packed)).array == [0x0a, 0x03, 0x80, 0x01, 0x02]);
    assert([1, 2][0..0].toProtobufTagged!(Proto(1, "", Yes.packed), No.omitDefaultValues).array == [0x0a, 0x00]);
    assert([1, 2][0..0].toProtobufTagged!(Proto(1, "", Yes.packed)).empty);

    assert((int[int]).init.toProtobufTagged!(Proto(1)).empty);
    assert((int[int]).init.toProtobufTagged!(Proto(1), No.omitDefaultValues).empty);
    assert([1: 2].toProtobufTagged!(Proto(1)).array == [0x0a, 0x04, 0x08, 0x01, 0x10, 0x02]);
    assert([1: 2].toProtobufTagged!(Proto(1, ",fixed")).array ==
        [0x0a, 0x07, 0x08, 0x01, 0x15, 0x02, 0x00, 0x00, 0x00]);
}

auto toProtobufTag(Proto proto, T)()
{
    validateProto!(proto, T);

    return toProtobufVarint(proto.tag << 3 | wireType!(proto, T));
}

class ProtobufException : Exception
{
    this(string message = null, string file = __FILE__, size_t line = __LINE__,
        Throwable next = null) @safe pure nothrow
    {
        super(message, file, line, next);
    }
}

long fromProtobufVarint(R)(ref R inputRange)
if (isInputRange!R && is(ElementType!R : ubyte))
{
    import std.range : front, popFront;
    import std.traits : Unqual, Unsigned;

    alias E = Unqual!(Unsigned!(ElementType!R));

    size_t i = 0;
    long result = 0;
    E data;

    do
    {
        enforce!ProtobufException(!inputRange.empty, "Truncated message");
        data = cast(E) inputRange.front;
        inputRange.popFront;

        if (i == 9)
            enforce!ProtobufException(!(data & 0xfe), "Malformed varint encoding");

        result |= cast(long) (data & 0x7f) << (i++ * 7);
    } while (data & 0x80);

    return result;
}

unittest
{
    auto foo = toProtobufVarint(0);
    assert(fromProtobufVarint(foo) == 0);
    assert(foo.empty);

    foo = toProtobufVarint(1);
    assert(fromProtobufVarint(foo) == 1);
    assert(foo.empty);

    foo = toProtobufVarint(int.max);
    assert(fromProtobufVarint(foo) == int.max);
    assert(foo.empty);

    foo = toProtobufVarint(int.min);
    assert(fromProtobufVarint(foo) == int.min);
    assert(foo.empty);

    foo = toProtobufVarint(long.max);
    assert(fromProtobufVarint(foo) == long.max);
    assert(foo.empty);

    foo = toProtobufVarint(long.min);
    assert(fromProtobufVarint(foo) == long.min);
    assert(foo.empty);
}

T zagZig(T)(T value)
if (is(T == int) || is(T == long))
{
    return (value >>> 1) ^ -(value & 1);
}

unittest
{
    assert(zagZig(zigZag(0)) == 0);
    assert(zagZig(zigZag(-1)) == -1);
    assert(zagZig(zigZag(1L)) == 1L);
    assert(zagZig(zigZag(int.max)) == int.max);
    assert(zagZig(zigZag(int.min)) == int.min);
    assert(zagZig(zigZag(long.min)) == long.min);
}

T fromProtobuf(T, Proto proto = Proto(1), R)(ref R inputRange)
if (isInputRange!R && is(ElementType!R : ubyte) && (isBoolean!T || isIntegral!T || isFloatingPoint!T))
{
    validateProto!(proto, T);

    static if (proto.wire == "fixed" || isFloatingPoint!T)
    {
        import std.algorithm : copy;
        import std.bitmanip : littleEndianToNative;

        enum size = T.sizeof;
        R fieldRange = inputRange.takeN(size);
        ubyte[size] buffer;
        fieldRange.copy(buffer[]);

        return buffer.littleEndianToNative!T;
    }
    else static if (proto.wire == "zigzag")
    {
        return cast(T) zagZig(fromProtobufVarint(inputRange));
    }
    else
    {
        return cast(T) fromProtobufVarint(inputRange);
    }
}

T fromProtobuf(T, Proto proto = Proto(1), R)(ref R inputRange)
if (isInputRange!R && is(ElementType!R : ubyte) && (is(T == string) || is(T == bytes)))
{
    import std.array : array;

    validateProto!(proto, T);

    R fieldRange = inputRange.takeLengthPrefixed;

    return cast(T) fieldRange.array;
}

T fromProtobuf(T, Proto proto = Proto(1), R)(ref R inputRange)
if (isInputRange!R && is(ElementType!R : ubyte) && isArray!T && !is(T == string) && !is(T == bytes))
{
    import std.array : Appender;

    static assert(proto.packed, "Non-packed repeated fields have no bulk decoding");
    validateProto!(proto, T);

    enum elementProto =-Proto(proto.tag, proto.wire);
    R fieldRange = inputRange.takeLengthPrefixed;

    Appender!T result;
    while (!fieldRange.empty)
        result ~= fromProtobuf!(elementProto, ElementType!T)(fieldRange);

    return result.data;
}

T fromProtobuf(T, Proto proto = Proto(1), R)(ref R inputRange, T result = null)
if (isInputRange!R && is(ElementType!R : ubyte) && isAssociativeArray!T)
{
    import std.algorithm : findSplit;
    import std.conv : to;

    validateProto!(proto, T);

    enum wires = proto.wire.findSplit(",");
    enum keyProto = Proto(1, wires[0]);
    enum valueProto = Proto(2, wires[2]);
    KeyType!T key;
    ValueType!T value;
    ubyte fromProtobufrState;
    R fieldRange = inputRange.takeLengthPrefixed;

    while (!fieldRange.empty)
    {
        uint tag;
        WireType wire;

        fromProtobufTag(fieldRange, tag, wire);

        switch (tag)
        {
        case 1:
            enforce!ProtobufException((fromProtobufrState & 0x01) == 0, "Double map key");
            fromProtobufrState |= 0x01;
            enum wireExpected = wireType!(keyProto, KeyType!T);
            enforce!ProtobufException(wire == wireExpected, "Wrong wire format");
            key = fieldRange.fromProtobuf!(KeyType!T, keyProto);
            break;
        case 2:
            enforce!ProtobufException((fromProtobufrState & 0x02) == 0, "Double map value");
            fromProtobufrState |= 0x02;
            enum wireExpected = wireType!(valueProto, KeyType!T);
            enforce!ProtobufException(wire == wireExpected, "Wrong wire format");
            value = fieldRange.fromProtobuf!(ValueType!T, valueProto);
            break;
        default:
            enforce!ProtobufException(false, "Unexpected field tag " ~ tag.to!string ~ " while decoding a map");
            break;
        }
    }
    enforce!ProtobufException((fromProtobufrState & 0x03) == 0x03, "Incomplete map element");
    result[key] = value;

    return result;
}

unittest
{
    import std.array : array;

    auto buffer = true.toProtobuf.array;
    assert(buffer.fromProtobuf!bool);
    buffer = 10.toProtobuf.array;
    assert(buffer.fromProtobuf!int == 10);
    buffer = (-1).toProtobuf.array;
    assert(buffer.fromProtobuf!int == -1);
    buffer = (-1L).toProtobuf.array;
    assert(buffer.fromProtobuf!long == -1L);
    buffer = 0xffffffffffffffffUL.toProtobuf.array;
    assert(buffer.fromProtobuf!long == 0xffffffffffffffffUL);

    buffer = (0.0).toProtobuf.array;
    assert(buffer.fromProtobuf!double == 0.0);
    buffer = (0.0f).toProtobuf.array;
    assert(buffer.fromProtobuf!float == 0.0f);

    buffer = 1.toProtobuf!(Proto(1, "fixed")).array;
    assert(buffer.fromProtobuf!(int, Proto(1, "fixed")) == 1);
    buffer = (-1).toProtobuf!(Proto(1, "fixed")).array;
    assert(buffer.fromProtobuf!(int, Proto(1, "fixed")) == -1);
    buffer = 0xffffffffU.toProtobuf!(Proto(1, "fixed")).array;
    assert(buffer.fromProtobuf!(uint, Proto(1, "fixed")) == 0xffffffffU);
    buffer = 1L.toProtobuf!(Proto(1, "fixed")).array;
    assert(buffer.fromProtobuf!(long, Proto(1, "fixed")) == 1L);

    buffer = "abc".toProtobuf.array;
    assert(buffer.fromProtobuf!string == "abc");
    buffer = "".toProtobuf.array;
    assert(buffer.fromProtobuf!string.empty);
    buffer = (cast(bytes) [1, 2, 3]).toProtobuf.array;
    assert(buffer.fromProtobuf!bytes == (cast(bytes) [1, 2, 3]));
    buffer = (cast(bytes) []).toProtobuf.array;
    assert(buffer.fromProtobuf!bytes.empty);

    buffer = 1.toProtobuf!(Proto(1, "zigzag")).array;
    assert(buffer.fromProtobuf!(int, Proto(1, "zigzag")) == 1);
    buffer = (-1).toProtobuf!(Proto(1, "zigzag")).array;
    assert(buffer.fromProtobuf!(int, Proto(1, "zigzag")) == -1);
    buffer = 1L.toProtobuf!(Proto(1, "zigzag")).array;
    assert(buffer.fromProtobuf!(long, Proto(1, "zigzag")) == 1L);
    buffer = (-1L).toProtobuf!(Proto(1, "zigzag")).array;
    assert(buffer.fromProtobuf!(long, Proto(1, "zigzag")) == -1L);
}

T fromProtobuf(T, Proto proto = Proto(1), R)(ref R inputRange, T result = T.init)
if (isInputRange!R && is(ElementType!R : ubyte) && isAggregateType!T)
{
    import std.traits : hasMember;

    validateProto!(proto, T);

    static if (is(T == class))
    {
        if (result is null)
            result = new T;
    }

    static if (hasMember!(T, "fromProtobuf"))
    {
        return result.fromProtobuf(inputRange);
    }
    else
    {
        string generateCases()
        {
            import std.conv : to;

            string result;
            foreach (field; Message!T.fields)
            {
                alias FieldType = typeof(mixin("T." ~ field));
                alias fieldProto = Message!T.getProtoByField!field;

                result ~= "case " ~ fieldProto.tag.to!string ~ ":\n" ~
                    "    alias FieldType = typeof(result." ~ field ~ ");\n" ~
                    "    enum proto = Message!T.getProtoByField!\"" ~ field ~ "\";\n" ~
                    "    enum wireExpected = wireType!(proto, FieldType);\n" ~
                    "    enforce!ProtobufException(wire == wireExpected, \"Wrong wire format\");\n";
                static if (!isArray!FieldType || is(FieldType == string) || is(FieldType == bytes))
                {
                    static if (isAggregateType!FieldType)
                    {
                        result ~= "    R fieldRange = inputRange.takeLengthPrefixed;";
                        result ~= "    result." ~ field ~ " = fromProtobuf!(FieldType, proto)(fieldRange);\n";
                        result ~= "    assert(fieldRange.empty);";
                    }
                    else
                    {
                        result ~= "    result." ~ field ~ " = fromProtobuf!(FieldType, proto)(inputRange);\n";
                    }
                }
                else static if (fieldProto.packed)
                {
                    result ~= "    result." ~ field ~ " ~= fromProtobuf!(FieldType, proto)(inputRange);\n";
                }
                else static if (isAggregateType!(ElementType!FieldType))
                {
                    result ~= "    R fieldRange = inputRange.takeLengthPrefixed;";
                    result ~= "    result." ~ field ~ " ~= fromProtobuf!(ElementType!FieldType, proto)(fieldRange);\n";
                    result ~= "    assert(fieldRange.empty);";
                }
                else
                {
                    result ~= "    result." ~ field ~ " ~= fromProtobuf!(ElementType!FieldType, proto)(inputRange);\n";
                }
                result ~= "    break;\n";
            }
            return result;
        }

        while (!inputRange.empty)
        {
            uint tag;
            WireType wire;

            fromProtobufTag(inputRange, tag, wire);

            switch (tag)
            {
            mixin(generateCases);
            default:
                skipUnknown(inputRange, wire);
                break;
            }
        }
        return result;
    }
}

unittest
{
    static class Foo
    {
        @Proto(1) int bar;
        @Proto(3) bool qux;
        @Proto(2, "fixed") long baz;
    }

    ubyte[] buff = [0x08, 0x05, 0x11, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x01];
    auto foo = buff.fromProtobuf!Foo;
    assert(buff.empty);
    assert(foo.bar == 5);
    assert(foo.baz == 1);
    assert(foo.qux);
}

void fromProtobufTag(R)(ref R inputRange, ref uint tag, ref WireType wireType)
if (isInputRange!R && is(ElementType!R : ubyte))
{
    long tagWire = fromProtobufVarint(inputRange);

    wireType = cast(WireType) (tagWire & 0x07);
    tagWire >>>= 3;
    enforce!ProtobufException(tagWire > 0 && tagWire < (1<<29), "Tag value out of range");
    tag = cast(uint) tagWire;
}

R takeN(R)(ref R inputRange, size_t size)
{
    R result = inputRange.take(size);
    enforce!ProtobufException(result.length == size, "Truncated message");
    inputRange = inputRange.dropExactly(size);
    return result;
}

R takeLengthPrefixed(R)(ref R inputRange)
{
    long size = fromProtobufVarint(inputRange);
    enforce!ProtobufException(size >= 0, "Negative field length");
    return inputRange.takeN(size);
}

void skipUnknown(R)(ref R inputRange, WireType wireType)
if (isInputRange!R && is(ElementType!R : ubyte))
{
    void skipExactly(ref R inputRange, size_t n)
    {
        enforce!ProtobufException(inputRange.take(n).length == n, "Truncated message");
        inputRange = inputRange.dropExactly(n);
    }

    switch (wireType) with (WireType)
    {
    case varint:
        inputRange.fromProtobufVarint;
        break;
    case bits64:
        inputRange.takeN(8);
        break;
    case withLength:
        inputRange.takeLengthPrefixed;
        break;
    case bits32:
        inputRange.takeN(4);
        break;
    default:
        enforce!ProtobufException(false, "Unknown wire format");
        break;
    }
}

void validateProto(Proto proto, T)()
{
    static assert(proto.tag > 0 && proto.tag < (2 << 29));

    static if (isBoolean!T)
    {
        static assert(!proto.packed);
        static assert(proto.wire == "");
    }
    else static if (is(T == int) || is(T == uint) || is(T == long) || is(T == ulong))
    {
        static assert(!proto.packed);
        static assert(proto.wire == "" || proto.wire == "fixed" || proto.wire == "zigzag");
    }
    else static if (is(T == enum) && is(T : int))
    {
        static assert(!proto.packed);
        static assert(proto.wire == "");
    }
    else static if (isFloatingPoint!T)
    {
        static assert(!proto.packed);
        static assert(proto.wire == "");
    }
    else static if (is(T == string) || is(T == bytes))
    {
        static assert(!proto.packed);
        static assert(proto.wire == "");
    }
    else static if (isArray!T)
    {
        static assert(is(ElementType!T == string) || is(ElementType!T == bytes)
            || (!isArray!(ElementType!T) && !isAssociativeArray!(ElementType!T)));
        enum elementProto = Proto(proto.tag, proto.wire);

        validateProto!(elementProto, ElementType!T);
    }
    else static if (isAssociativeArray!T)
    {
        import std.algorithm : findSplit;

        static assert(!proto.packed);
        static assert(isBoolean!(KeyType!T) || isIntegral!(KeyType!T) || is(KeyType!T == string));
        static assert(is(ValueType!T == string) || is(ValueType!T == bytes)
            || (!isArray!(ValueType!T) && !isAssociativeArray!(ValueType!T)));

        enum wires = proto.wire.findSplit(",");

        enum keyProto = Proto(1, wires[0]);
        validateProto!(keyProto, KeyType!T);

        enum valueProto = Proto(2, wires[2]);
        validateProto!(valueProto, ValueType!T);
    }
    else static if (isAggregateType!T)
    {
        static assert(!proto.packed);
        static assert(proto.wire == "");
    }
    else
    {
        static assert(0, "Invalid Proto definition for type " ~ T.stringof);
    }
}

WireType wireType(Proto proto, T)()
{
    validateProto!(proto, T);

    static if (is(T == string) || is(T == bytes) || (isArray!T && proto.packed) || isAssociativeArray!T ||
        isAggregateType!T)
    {
        return WireType.withLength;
    }
    else static if (isArray!T && !proto.packed)
    {
        return wireType!(proto, ElementType!T);
    }
    else static if (((is(T == long) || is(T == ulong)) && proto.wire == "fixed") || is(T == double))
    {
        return WireType.bits64;
    }
    else static if (((is(T == int) || is(T == uint)) && proto.wire == "fixed") || is(T == float))
    {
        return WireType.bits32;
    }
    else static if (isBoolean!T || isIntegral!T)
    {
        return WireType.varint;
    }
    else
    {
        static assert(0, "Internal error");
    }
}

private template arrayToAliasSeq(alias arr)
{
    import std.meta : AliasSeq;

    static if (arr.length == 0)
        alias arrayToAliasSeq = AliasSeq!();
    else static if (arr.length == 1)
        alias arrayToAliasSeq = AliasSeq!(arr[0]);
    else
        alias arrayToAliasSeq = AliasSeq!(arrayToAliasSeq!(arr[0 .. $/2]),
            arrayToAliasSeq!(arr[$/2 .. $]));
}

auto defaultValue(T)()
{
    static if (isFloatingPoint!T)
        return cast(T) 0.0;
    else
        return T.init;
}

auto joiner(RoR)(RoR ranges)
if (isInputRange!RoR && isInputRange!(ElementType!RoR) && hasLength!(ElementType!RoR))
{
    import std.algorithm : stdJoiner = joiner, sum;
    alias StdJoinerResult = typeof(stdJoiner(ranges));

    static struct Result
    {
        StdJoinerResult result;
        size_t _length;

        alias result this;

        this(RoR r)
        {
            result = StdJoinerResult(r);
            _length = r.map!(a => a.length).sum;
        }

        void popFront()
        {
            result.popFront;
            --_length;
        }

        @property size_t length()
        {
            return _length;
        }
    }

    return Result(ranges);
}

unittest
{
    import std.array : array;

    auto a = [[1, 2, 3], [], [4, 5]].joiner;

    assert(a.length == 5);
    a.popFront;
    assert(a.length == 4);
    assert(a.array == [2, 3, 4, 5]);
}

interface SizedRange(E) : InputRange!E
{
    @property size_t length();
}

class SizedRangeObject(R) : InputRangeObject!R, SizedRange!(ElementType!R)
if (isInputRange!R && hasLength!R)
{
    size_t _length;

    this(R range)
    {
        super(range);
        _length = range.length;
    }

    override void popFront()
    {
        super.popFront;
        --_length;
    }

    override @property size_t length()
    {
        return _length;
    }
}

SizedRangeObject!R sizedRangeObject(R)(R range)
if (isInputRange!R && hasLength!R)
{
    static if (is(R : SizedRange!(ElementType!R)))
        return range;
    else
        return new SizedRangeObject!R(range);
}
