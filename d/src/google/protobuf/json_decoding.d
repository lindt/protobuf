module google.protobuf.json_decoding;

import std.exception : enforce;
import std.json : JSON_TYPE, JSONValue;
import std.traits : isAggregateType, isArray, isAssociativeArray, isBoolean, isFloatingPoint, isIntegral, isSigned;
import std.typecons : Flag, No, Yes;
import google.protobuf.common;

T fromJSONValue(T)(JSONValue value)
if (isBoolean!T)
{
    switch (value.type)
    {
    case JSON_TYPE.FALSE:
        return false;
    case JSON_TYPE.TRUE:
        return true;
    default:
        throw new ProtobufException("Boolean JSONValue expected");
    }
}

T fromJSONValue(T)(JSONValue value)
if (isIntegral!T && isSigned!T)
{
    enforce!ProtobufException(value.type == JSON_TYPE.INTEGER, "Integer JSONValue expected");
    return cast(T) value.integer;
}

T fromJSONValue(T)(JSONValue value)
if (isIntegral!T && !isSigned!T)
{
    enforce!ProtobufException(value.type == JSON_TYPE.UINTEGER, "Unsigned integer JSONValue expected");
    return cast(T) value.uinteger;
}

T fromJSONValue(T)(JSONValue value)
if (isFloatingPoint!T)
{
    import std.math : isInfinity, isNaN;

    switch (value.type)
    {
    case JSON_TYPE.FLOAT:
        return value.floating;
    case JSON_TYPE.STRING:
        switch (value.str)
        {
        case "NaN":
            return T.nan;
        case "Infinity":
            return T.infinity;
        case "-Infinity":
            return -T.infinity;
        default:
            throw new ProtobufException("Wrong float literal");
        }
    default:
        throw new ProtobufException("Floating point JSONValue expected");
    }
}

T fromJSONValue(T)(JSONValue value)
if (is(T == string))
{
    enforce!ProtobufException(value.type == JSON_TYPE.STRING, "String JSONValue expected");
    return value.str;
}

T fromJSONValue(T)(JSONValue value)
if (is(T == bytes))
{
    import std.base64 : Base64;

    enforce!ProtobufException(value.type == JSON_TYPE.STRING, "String JSONValue expected");
    return Base64.decode(value.str);
}

T fromJSONValue(T)(JSONValue value)
if (isArray!T && !is(T == string) && !is(T == bytes))
{
    import std.algorithm : map;
    import std.array : array;
    import std.range : ElementType;

    enforce!ProtobufException(value.type == JSON_TYPE.ARRAY, "Array JSONValue expected");
    return value.array.map!(a => a.fromJSONValue!(ElementType!T)).array;
}

T fromJSONValue(T)(JSONValue value, T result = null)
if (isAssociativeArray!T)
{
    import std.conv : ConvException, to;
    import std.traits : KeyType, ValueType;

    enforce!ProtobufException(value.type == JSON_TYPE.OBJECT, "Object JSONValue expected");
    foreach (k, v; value.object)
    {
        try
        {
            result[k.to!(KeyType!T)] = v.fromJSONValue!(ValueType!T);
        }
        catch (ConvException exception)
        {
            throw new ProtobufException(exception.msg);
        }
    }

    return result;
}

unittest
{
    import std.exception : assertThrown;
    import std.json : parseJSON;
    import std.math : isInfinity, isNaN;

    assert(fromJSONValue!bool(JSONValue(false)) == false);
    assert(fromJSONValue!bool(JSONValue(true)) == true);
    assertThrown!ProtobufException(fromJSONValue!bool(JSONValue(1)));

    assert(fromJSONValue!int(JSONValue(1)) == 1);
    assert(fromJSONValue!uint(JSONValue(1U)) == 1U);
    assert(fromJSONValue!long(JSONValue(1L)) == 1);
    assert(fromJSONValue!ulong(JSONValue(1UL)) == 1U);
    assertThrown!ProtobufException(fromJSONValue!int(JSONValue(false)));
    assertThrown!ProtobufException(fromJSONValue!ulong(JSONValue("foo")));

    assert(fromJSONValue!float(JSONValue(1.0f)) == 1.0);
    assert(fromJSONValue!double(JSONValue(1.0)) == 1.0);
    assert(fromJSONValue!float(JSONValue("NaN")).isNaN);
    assert(fromJSONValue!double(JSONValue("Infinity")).isInfinity);
    assert(fromJSONValue!double(JSONValue("-Infinity")).isInfinity);
    assertThrown!ProtobufException(fromJSONValue!float(JSONValue(false)));
    assertThrown!ProtobufException(fromJSONValue!double(JSONValue("foo")));

    assert(fromJSONValue!bytes(JSONValue("Zm9v")) == cast(bytes) "foo");
    assertThrown!ProtobufException(fromJSONValue!bytes(JSONValue(1)));

    assert(fromJSONValue!(int[])(parseJSON(`[1, 2, 3]`)) == [1, 2, 3]);
    assertThrown!ProtobufException(fromJSONValue!(int[])(JSONValue(`[1, 2, 3]`)));

    assert(fromJSONValue!(bool[int])(parseJSON(`{"1": false, "2": true}`)) == [1 : false, 2 : true]);
    assertThrown!ProtobufException(fromJSONValue!(bool[int])(JSONValue(`{"1": false, "2": true}`)));
    assertThrown!ProtobufException(fromJSONValue!(bool[int])(parseJSON(`{"foo": false, "2": true}`)));
}

T fromJSONValue(T)(JSONValue value, T result = T.init)
if (isAggregateType!T)
{
    import std.traits : hasMember;

    enforce!ProtobufException(value.type == JSON_TYPE.OBJECT, "Object JSONValue expected");

    static if (is(T == class))
    {
        if (result is null)
            result = new T;
    }

    static if (hasMember!(T, "fromJSONValue"))
    {
        return result.fromJSONValue(value);
    }
    else
    {
        JSONValue[string] members = value.object;

        foreach (field; Message!T.fieldNames)
        {
            static if (field[$ - 1] == '_')
                enum jsonName = field[0 .. $ - 1];
            else
                enum jsonName = field;

            auto fieldValue = (jsonName in members);
            if (fieldValue !is null)
                mixin("result." ~ field) = fromJSONValue!(typeof(mixin("T." ~ field)))(*fieldValue);
        }
        return result;
    }
}

unittest
{
    import std.exception : assertThrown;
    import std.json : parseJSON;

    struct Foo
    {
        @Proto(1) int a;
        @Proto(3) string b;
        @Proto(4) bool c;
    }

    auto foo = Foo(10, "abc", false);

    assert(fromJSONValue!Foo(parseJSON(`{"a":10, "b":"abc"}`)) == Foo(10, "abc", false));
    assert(fromJSONValue!Foo(parseJSON(`{"a": 10, "b": "abc", "c": false}`)) == Foo(10, "abc", false));
    assertThrown!ProtobufException(fromJSONValue!Foo(parseJSON(`{"a":10, "b":100}`)));
}
