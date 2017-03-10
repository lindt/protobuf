module google.protobuf.decoding;

import std.algorithm : map;
import std.exception : enforce;
import std.range : chain, dropExactly, ElementType, empty, hasLength, isInputRange, take;
import std.traits : isAggregateType, isArray, isAssociativeArray, isBoolean, isFloatingPoint, isIntegral, KeyType,
    ValueType;
import google.protobuf.common;
import google.protobuf.internal;

/*
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
        return cast(T) zagZig(fromVarint(inputRange));
    }
    else
    {
        return cast(T) fromVarint(inputRange);
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
    long tagWire = fromVarint(inputRange);

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
    long size = fromVarint(inputRange);
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
        inputRange.fromVarint;
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
*/
