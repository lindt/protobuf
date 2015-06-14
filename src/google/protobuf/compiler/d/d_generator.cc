// Protocol Buffers - Google's data interchange format
// Copyright 2008 Google Inc.  All rights reserved.
// https://developers.google.com/protocol-buffers/
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//     * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//     * Neither the name of Google Inc. nor the names of its
// contributors may be used to endorse or promote products derived from
// this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include <algorithm>
#include <set>
#include <vector>

#include <google/protobuf/compiler/code_generator.h>
#include <google/protobuf/compiler/d/d_helpers.h>
#include <google/protobuf/compiler/plugin.h>
#include <google/protobuf/descriptor.h>
#include <google/protobuf/descriptor.pb.h>
#include <google/protobuf/io/printer.h>
#include <google/protobuf/io/zero_copy_stream.h>
#include <google/protobuf/stubs/strutil.h>

#include <google/protobuf/compiler/d/d_generator.h>

using google::protobuf::internal::scoped_ptr;

namespace google {
namespace protobuf {
namespace compiler {
namespace d {

// Forward decls.
void GenerateMessage(const Descriptor* message, io::Printer* printer);
void GenerateEnum(const EnumDescriptor* en, io::Printer* printer);

void GenerateField(const FieldDescriptor* field, io::Printer* printer,
                   bool print_initializer) {
  printer->Print(
    "@Proto($number$",
    "number", SimpleItoa(field->number()));
  if (WireFormat(field).length()) {
    printer->Print(
      ", \"$format$\"",
      "format", WireFormat(field));
  }
  printer->Print(
    ") $type$ $name$",
    "name", EscapeKeywords(field->camelcase_name()),
    "type", TypeName(field));
  if (print_initializer) {
    printer->Print(
      " = defaultValue!($type$)",
      "type", TypeName(field));
  }
  printer->Print(";\n");
}

void GenerateOneofCaseEnum(const OneofDescriptor* oneof,
                           io::Printer* printer) {
  printer->Print(
    "enum $Name$Case\n{\n",
    "Name", UnderscoresToCamelCase(oneof->name(), true));
  printer->Indent();
  printer->Indent();
  printer->Print(
    "case$Name$NotSet = 0,\n",
    "Name", UnderscoresToCamelCase(oneof->name(), true));

  for (int i = 0; i < oneof->field_count(); i++) {
    const FieldDescriptor* field = oneof->field(i);
    printer->Print("case$Name$ = $number$,\n",
      "Name", UnderscoresToCamelCase(field->name(), true),
      "number", SimpleItoa(field->number()));
  }

  printer->Outdent();
  printer->Outdent();
  printer->Print(
    "}\nprivate $Name$Case $name$Case_ = $Name$Case.case$Name$NotSet;\n"
    "@property $Name$Case $name$Case() { return $name$Case_; }\n"
    "void clear$Name$() { $name$Case_ = $Name$Case.case$Name$NotSet; }\n",
    "Name", UnderscoresToCamelCase(oneof->name(), true),
    "name", UnderscoresToCamelCase(oneof->name(), false));
}

void GenerateOneofUnion(const OneofDescriptor* oneof, io::Printer* printer) {
  printer->Print(
    "union $name$\n{\n",
    "name", UnderscoresToCamelCase(oneof->name(), true));
  printer->Indent();
  printer->Indent();

  for (int i = 0; i < oneof->field_count(); i++) {
    const FieldDescriptor* field = oneof->field(i);
    GenerateField(field, printer, i == 0);
  }

  printer->Outdent();
  printer->Outdent();
  printer->Print(
    "}\nprivate $Name$ $name$;\n",
    "Name", UnderscoresToCamelCase(oneof->name(), true),
    "name", UnderscoresToCamelCase(oneof->name(), false));
}

void GenerateOneofGetter(const OneofDescriptor* oneof,
                         const FieldDescriptor* field,
                         io::Printer* printer) {
  printer->Print(
    "@property @Proto($number$",
    "number", SimpleItoa(field->number()));
  if (WireFormat(field).length()) {
    printer->Print(
      ", \"$format$\"",
      "format", WireFormat(field));
  }
  printer->Print(
    ") $type$ $name$() { return $oneof$Case == $Oneof$Case.case$Name$ ? "
    "$oneof$.$name$ : defaultValue!($type$); }\n",
    "Name", UnderscoresToCamelCase(field->name(), true),
    "name", UnderscoresToCamelCase(field->name(), false),
    "type", TypeName(field),
    "Oneof", UnderscoresToCamelCase(oneof->name(), true),
    "oneof", UnderscoresToCamelCase(oneof->name(), false));
}

void GenerateOneofSetter(const OneofDescriptor* oneof,
                         const FieldDescriptor* field,
                         io::Printer* printer) {
  printer->Print(
    "@property void $name$($type$ value) { "
    "$oneof$Case_ = $Oneof$Case.case$Name$; $oneof$.$name$ = value; }\n",
    "Name", UnderscoresToCamelCase(field->name(), true),
    "name", UnderscoresToCamelCase(field->name(), false),
    "type", TypeName(field),
    "Oneof", UnderscoresToCamelCase(oneof->name(), true),
    "oneof", UnderscoresToCamelCase(oneof->name(), false));
}

void GenerateOneofAccessors(const OneofDescriptor* oneof,
                            io::Printer* printer) {
  for (int i = 0; i < oneof->field_count(); i++) {
    const FieldDescriptor* field = oneof->field(i);
    GenerateOneofGetter(oneof, field, printer);
    GenerateOneofSetter(oneof, field, printer);
  }
}

void GenerateOneof(const OneofDescriptor* oneof, io::Printer* printer) {
  GenerateOneofCaseEnum(oneof, printer);
  GenerateOneofUnion(oneof, printer);
  GenerateOneofAccessors(oneof, printer);
}

bool cmp_by_tag(const FieldDescriptor* a, const FieldDescriptor* b) {
  return a->number() < b->number();
}

void GenerateMessage(const Descriptor* message, io::Printer* printer) {
  // Don't generate MapEntry messages.
  if (message->options().map_entry()) {
    return;
  }

  if (message->containing_type()) {
    printer->Print("\nstatic ");
  }

  printer->Print(
    "class $name$\n{\n",
    "name", EscapeKeywords(message->name()));
  printer->Indent();
  printer->Indent();

  std::vector<const FieldDescriptor*> ordered_fields;
  for (int i = 0; i < message->field_count(); i++) {
    ordered_fields.push_back(message->field(i));
  }
  std::sort(ordered_fields.begin(), ordered_fields.end(), cmp_by_tag);

  std::vector<const OneofDescriptor*> generated_oneofs;
  for (std::vector<const FieldDescriptor*>::iterator it =
      ordered_fields.begin(); it != ordered_fields.end(); ++it) {
    const FieldDescriptor* field = *it;
    const OneofDescriptor* oneof = field->containing_oneof();
    if (oneof) {
      if (std::find(generated_oneofs.begin(), generated_oneofs.end(), oneof) ==
          generated_oneofs.end()) {
        generated_oneofs.push_back(oneof);
        GenerateOneof(oneof, printer);
      }
    } else {
      GenerateField(field, printer, true);
    }
  }

  for (int i = 0; i < message->nested_type_count(); i++) {
    GenerateMessage(message->nested_type(i), printer);
  }
  for (int i = 0; i < message->enum_type_count(); i++) {
    printer->Print("\n");
    GenerateEnum(message->enum_type(i), printer);
  }

  printer->Outdent();
  printer->Outdent();
  printer->Print("}\n");
}

void GenerateEnum(const EnumDescriptor* en, io::Printer* printer) {
  printer->Print(
    "enum $name$\n{\n",
    "name", EscapeKeywords(en->name()));
  printer->Indent();
  printer->Indent();

  for (int i = 0; i < en->value_count(); i++) {
    const EnumValueDescriptor* value = en->value(i);
    printer->Print(
      "$name$ = $number$,\n",
      "name", EscapeKeywords(value->name()),
      "number", SimpleItoa(value->number()));
  }

  printer->Outdent();
  printer->Outdent();
  printer->Print(
    "}\n");
}

void GenerateFile(const FileDescriptor* file, io::Printer* printer) {
  printer->Print(
    "// Generated by the protocol buffer compiler.  DO NOT EDIT!\n"
    "// source: $filename$\n",
    "filename", file->name());

  printer->Print(
    "module $module$;\n\n",
    "module", ModuleName(file));

  printer->Print(
    "import google.protobuf;\n");

  for (int i = 0; i < file->dependency_count(); i++) {
    printer->Print(
      "import $module$;\n",
      "module", ModuleName(file->dependency(i)));
  }

  for (int i = 0; i < file->message_type_count(); i++) {
    printer->Print("\n");
    GenerateMessage(file->message_type(i), printer);
  }
  for (int i = 0; i < file->enum_type_count(); i++) {
    printer->Print("\n");
    GenerateEnum(file->enum_type(i), printer);
  }
}

bool Generator::Generate(
    const FileDescriptor* file,
    const string& parameter,
    GeneratorContext* generator_context,
    string* error) const {
  if (file->syntax() != FileDescriptor::SYNTAX_PROTO3) {
    *error =
        "Can only generate D code for proto3 .proto files.\n"
        "Please add 'syntax = \"proto3\";' to the top of your .proto file.\n";
    return false;
  }

  string filename = EscapeKeywords(
    StripSuffixString(file->name(), ".proto"), '/') + ".d";
  scoped_ptr<io::ZeroCopyOutputStream> output(
      generator_context->Open(filename));
  io::Printer printer(output.get(), '$');

  GenerateFile(file, &printer);

  return true;
}

}  // namespace d
}  // namespace compiler
}  // namespace protobuf
}  // namespace google
