// Generated by the protocol buffer compiler.  DO NOT EDIT!
// source: generated_code.proto
module A.B.C.generated_code;

import google.protobuf;

class TestMessage
{
    @Proto(1) int optionalInt32 = defaultValue!(int);
    @Proto(2) long optionalInt64 = defaultValue!(long);
    @Proto(3) uint optionalUint32 = defaultValue!(uint);
    @Proto(4) ulong optionalUint64 = defaultValue!(ulong);
    @Proto(5) bool optionalBool = defaultValue!(bool);
    @Proto(6) double optionalDouble = defaultValue!(double);
    @Proto(7) float optionalFloat = defaultValue!(float);
    @Proto(8) string optionalString = defaultValue!(string);
    @Proto(9) bytes optionalBytes = defaultValue!(bytes);
    @Proto(10) TestEnum optionalEnum = defaultValue!(TestEnum);
    @Proto(11) TestMessage optionalMsg = defaultValue!(TestMessage);
    @Proto(21) int[] repeatedInt32 = defaultValue!(int[]);
    @Proto(22) long[] repeatedInt64 = defaultValue!(long[]);
    @Proto(23) uint[] repeatedUint32 = defaultValue!(uint[]);
    @Proto(24) ulong[] repeatedUint64 = defaultValue!(ulong[]);
    @Proto(25) bool[] repeatedBool = defaultValue!(bool[]);
    @Proto(26) double[] repeatedDouble = defaultValue!(double[]);
    @Proto(27) float[] repeatedFloat = defaultValue!(float[]);
    @Proto(28) string[] repeatedString = defaultValue!(string[]);
    @Proto(29) bytes[] repeatedBytes = defaultValue!(bytes[]);
    @Proto(30) TestEnum[] repeatedEnum = defaultValue!(TestEnum[]);
    @Proto(31) TestMessage[] repeatedMsg = defaultValue!(TestMessage[]);
    enum MyOneofCase
    {
        caseMyOneofNotSet = 0,
        caseOneofInt32 = 41,
        caseOneofInt64 = 42,
        caseOneofUint32 = 43,
        caseOneofUint64 = 44,
        caseOneofBool = 45,
        caseOneofDouble = 46,
        caseOneofFloat = 47,
        caseOneofString = 48,
        caseOneofBytes = 49,
        caseOneofEnum = 50,
        caseOneofMsg = 51,
    }
    private MyOneofCase myOneofCase_ = MyOneofCase.caseMyOneofNotSet;
    @property MyOneofCase myOneofCase() { return myOneofCase_; }
    void clearMyOneof() { myOneofCase_ = MyOneofCase.caseMyOneofNotSet; }
    union MyOneof
    {
        @Proto(41) int oneofInt32 = defaultValue!(int);
        @Proto(42) long oneofInt64;
        @Proto(43) uint oneofUint32;
        @Proto(44) ulong oneofUint64;
        @Proto(45) bool oneofBool;
        @Proto(46) double oneofDouble;
        @Proto(47) float oneofFloat;
        @Proto(48) string oneofString;
        @Proto(49) bytes oneofBytes;
        @Proto(50) TestEnum oneofEnum;
        @Proto(51) TestMessage oneofMsg;
    }
    private MyOneof myOneof;
    @property @Proto(41) int oneofInt32() { return myOneofCase == MyOneofCase.caseOneofInt32 ? myOneof.oneofInt32 : defaultValue!(int); }
    @property void oneofInt32(int value) { myOneofCase_ = MyOneofCase.caseOneofInt32; myOneof.oneofInt32 = value; }
    @property @Proto(42) long oneofInt64() { return myOneofCase == MyOneofCase.caseOneofInt64 ? myOneof.oneofInt64 : defaultValue!(long); }
    @property void oneofInt64(long value) { myOneofCase_ = MyOneofCase.caseOneofInt64; myOneof.oneofInt64 = value; }
    @property @Proto(43) uint oneofUint32() { return myOneofCase == MyOneofCase.caseOneofUint32 ? myOneof.oneofUint32 : defaultValue!(uint); }
    @property void oneofUint32(uint value) { myOneofCase_ = MyOneofCase.caseOneofUint32; myOneof.oneofUint32 = value; }
    @property @Proto(44) ulong oneofUint64() { return myOneofCase == MyOneofCase.caseOneofUint64 ? myOneof.oneofUint64 : defaultValue!(ulong); }
    @property void oneofUint64(ulong value) { myOneofCase_ = MyOneofCase.caseOneofUint64; myOneof.oneofUint64 = value; }
    @property @Proto(45) bool oneofBool() { return myOneofCase == MyOneofCase.caseOneofBool ? myOneof.oneofBool : defaultValue!(bool); }
    @property void oneofBool(bool value) { myOneofCase_ = MyOneofCase.caseOneofBool; myOneof.oneofBool = value; }
    @property @Proto(46) double oneofDouble() { return myOneofCase == MyOneofCase.caseOneofDouble ? myOneof.oneofDouble : defaultValue!(double); }
    @property void oneofDouble(double value) { myOneofCase_ = MyOneofCase.caseOneofDouble; myOneof.oneofDouble = value; }
    @property @Proto(47) float oneofFloat() { return myOneofCase == MyOneofCase.caseOneofFloat ? myOneof.oneofFloat : defaultValue!(float); }
    @property void oneofFloat(float value) { myOneofCase_ = MyOneofCase.caseOneofFloat; myOneof.oneofFloat = value; }
    @property @Proto(48) string oneofString() { return myOneofCase == MyOneofCase.caseOneofString ? myOneof.oneofString : defaultValue!(string); }
    @property void oneofString(string value) { myOneofCase_ = MyOneofCase.caseOneofString; myOneof.oneofString = value; }
    @property @Proto(49) bytes oneofBytes() { return myOneofCase == MyOneofCase.caseOneofBytes ? myOneof.oneofBytes : defaultValue!(bytes); }
    @property void oneofBytes(bytes value) { myOneofCase_ = MyOneofCase.caseOneofBytes; myOneof.oneofBytes = value; }
    @property @Proto(50) TestEnum oneofEnum() { return myOneofCase == MyOneofCase.caseOneofEnum ? myOneof.oneofEnum : defaultValue!(TestEnum); }
    @property void oneofEnum(TestEnum value) { myOneofCase_ = MyOneofCase.caseOneofEnum; myOneof.oneofEnum = value; }
    @property @Proto(51) TestMessage oneofMsg() { return myOneofCase == MyOneofCase.caseOneofMsg ? myOneof.oneofMsg : defaultValue!(TestMessage); }
    @property void oneofMsg(TestMessage value) { myOneofCase_ = MyOneofCase.caseOneofMsg; myOneof.oneofMsg = value; }
    @Proto(61) string[int] mapInt32String = defaultValue!(string[int]);
    @Proto(62) string[long] mapInt64String = defaultValue!(string[long]);
    @Proto(63) string[uint] mapUint32String = defaultValue!(string[uint]);
    @Proto(64) string[ulong] mapUint64String = defaultValue!(string[ulong]);
    @Proto(65) string[bool] mapBoolString = defaultValue!(string[bool]);
    @Proto(66) string[string] mapStringString = defaultValue!(string[string]);
    @Proto(67) TestMessage[string] mapStringMsg = defaultValue!(TestMessage[string]);
    @Proto(68) TestEnum[string] mapStringEnum = defaultValue!(TestEnum[string]);
    @Proto(69) int[string] mapStringInt32 = defaultValue!(int[string]);
    @Proto(70) bool[string] mapStringBool = defaultValue!(bool[string]);
    @Proto(80) NestedMessage nestedMessage = defaultValue!(NestedMessage);

    static class NestedMessage
    {
        @Proto(1) int foo = defaultValue!(int);
    }
}

enum TestEnum
{
    Default = 0,
    A = 1,
    B = 2,
    C = 3,
}
