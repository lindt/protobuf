module google.protobuf.json_encoding;

import std.json : JSONValue;
import std.traits : isAggregateType, isArray, isAssociativeArray, isBoolean, isFloatingPoint, isIntegral, isSigned;
import std.typecons : Flag, No, Yes;
import google.protobuf.common;

JSONValue toJSONValue(T)(T value)
if (isBoolean!T || isIntegral!T || is(T == string))
{
    return JSONValue(value);
}

JSONValue toJSONValue(T)(T value)
if (isFloatingPoint!T)
{
    import std.math : isInfinity, isNaN;

    if (value.isNaN)
        return JSONValue("NaN");
    else if (value.isInfinity)
        return JSONValue(value < 0 ? "-Infinity" : "Infinity");
    else
        return JSONValue(value);
}

JSONValue toJSONValue(T)(T value)
if (is(T == bytes))
{
    import std.base64 : Base64;

    return JSONValue(cast(string) Base64.encode(value));
}

JSONValue toJSONValue(T)(T value)
if (isArray!T && !is(T == string) && !is(T == bytes))
{
    import std.algorithm : map;
    import std.array : array;

    return JSONValue(value.map!(a => a.toJSONValue).array);
}

JSONValue toJSONValue(T)(T value)
if (isAssociativeArray!T)
{
    import std.conv : to;

    JSONValue[string] members;

    foreach (k, v; value)
        members[k.to!string] = toJSONValue(v);

    return JSONValue(members);
}

unittest
{
    import std.json : parseJSON, toJSON;

    assert(toJSONValue(true) == JSONValue(true));
    assert(toJSONValue(false) == JSONValue(false));
    assert(toJSONValue(1) == JSONValue(1));
    assert(toJSONValue(1U) == JSONValue(1U));
    assert(toJSONValue(1L) == JSONValue(1));
    assert(toJSONValue(1UL) == JSONValue(1U));
    assert(toJSONValue(1.0f) == JSONValue(1.0));
    assert(toJSONValue(1.0) == JSONValue(1.0));

    auto jsonValue = toJSONValue(double.nan);
    assert(toJSON(jsonValue) ==`"NaN"`);
    jsonValue = toJSONValue(float.infinity);
    assert(toJSON(jsonValue) == `"Infinity"`);
    jsonValue = toJSONValue(-double.infinity);
    assert(toJSON(jsonValue) == `"-Infinity"`);

    assert(toJSONValue(cast(bytes) "foo") == JSONValue("Zm9v"));
    assert(toJSONValue([1, 2, 3]) == parseJSON(`[1, 2, 3]`));
    assert([1 : false, 2 : true].toJSONValue == parseJSON(`{"1": false, "2": true}`));
}

JSONValue toJSONValue(Flag!"omitDefaultValues" omitDefaultValues = Yes.omitDefaultValues, T)(T value)
if (isAggregateType!T)
{
    import std.meta : AliasSeq;
    import std.traits : hasMember;

    static if (hasMember!(T, "toJSONValue"))
    {
        return value.toJSONValue;
    }
    else
    {
        JSONValue[string] members;

        foreach (field; Message!T.fieldNames)
        {
            auto fieldValue = mixin("value." ~ field);
            alias FieldType = typeof(fieldValue);

            static if (isAggregateType!FieldType)
            {
                static if (omitDefaultValues)
                {
                    if (fieldValue != defaultValue!FieldType)
                        members[field] = toJSONValue!omitDefaultValues(fieldValue);
                }
                else
                {
                    members[field] = toJSONValue!omitDefaultValues(fieldValue);
                }
            }
            else
            {
                static if (omitDefaultValues)
                {
                    if (fieldValue != defaultValue!FieldType)
                        members[field] = fieldValue.toJSONValue;
                }
                else
                {
                    members[field] = fieldValue.toJSONValue;
                }
            }
        }

        return JSONValue(members);
    }
}

unittest
{
    import std.json : parseJSON;

    struct Foo
    {
        @Proto(1) int a;
        @Proto(3) string b;
        @Proto(4) bool c;
    }

    auto foo = Foo(10, "abc", false);

    assert(foo.toJSONValue == parseJSON(`{"a":10, "b":"abc"}`));
    assert(foo.toJSONValue!(No.omitDefaultValues) == parseJSON(`{"a": 10, "b": "abc", "c": false}`));
}
