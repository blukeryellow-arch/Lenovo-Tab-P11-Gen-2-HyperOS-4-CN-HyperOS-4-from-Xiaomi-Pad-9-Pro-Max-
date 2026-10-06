#!/usr/bin/env python3
"""Generator /system/etc/classpaths/bootclasspath.pb (BINARY proto, proto3).

Schemat (AOSP packages/modules/common/proto/classpaths.proto):
  enum Classpath { UNKNOWN=0; BOOTCLASSPATH=1; SYSTEMSERVERCLASSPATH=2;
                   DEX2OATBOOTCLASSPATH=3; STANDALONE_SYSTEMSERVER_JARS=4; }
  message Jar { string path=1; Classpath classpath=2;
                string min_sdk_version=3; string max_sdk_version=4; }
  message ExportedClasspathsJars { repeated Jar jars=1; }

Skad to wiemy: derive_classpath.cpp (SdkExtensions; Android 12+) globuje
  1) /apex/com.android.art/etc/classpaths/bootclasspath.pb (pierwszy)
  2) /system/etc/classpaths/bootclasspath.pb   <-- TEN PLIK
  3) /apex/*/etc/classpaths/bootclasspath.pb
i scala jary do export BOOTCLASSPATH (init load_exports). Czyli: jary miui
trafiaja na BOOTCLASSPATH BEZ dotykania boot.img (kernel/init zostaja stock).

Uzycie:
  mkclasspathpb.py build <out.pb> <jar-sciezka-abs>...   # buduje + samodekoduje
  mkclasspathpb.py verify <in.pb> <jar-abs>...           # twarda weryfikacja
"""
import sys

BOOTCLASSPATH = 1


def _varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def _ld(field, payload):
    """length-delimited: (field<<3)|2, varint(len), payload"""
    return bytes([(field << 3) | 2]) + _varint(len(payload)) + payload


def _vi(field, val):
    """varint: (field<<3)|0, varint(val)"""
    return bytes([(field << 3) | 0]) + _varint(val)


def _jar(path):
    return _ld(1, path.encode()) + _vi(2, BOOTCLASSPATH)


def build(jars):
    return b"".join(_ld(1, _jar(p)) for p in jars)


def _fields(data):
    i = 0
    while i < len(data):
        tag = data[i]
        i += 1
        f, wt = tag >> 3, tag & 7
        if wt == 0:
            v = sh = 0
            while True:
                b = data[i]
                i += 1
                v |= (b & 0x7F) << sh
                sh += 7
                if not b & 0x80:
                    break
            yield f, v
        elif wt == 2:
            n = sh = 0
            while True:
                b = data[i]
                i += 1
                n |= (b & 0x7F) << sh
                sh += 7
                if not b & 0x80:
                    break
            yield f, data[i:i + n]
            i += n
        else:
            raise ValueError("niespodziewany wire type %d" % wt)


def decode(data):
    jars = []
    for f, payload in _fields(data):
        if f != 1:
            continue
        path = None
        cp = None
        for f2, v2 in _fields(payload):
            if f2 == 1:
                path = v2.decode()
            elif f2 == 2:
                cp = v2
        jars.append((path, cp))
    return jars


def main():
    mode = sys.argv[1]
    if mode == "build":
        out, jars = sys.argv[2], sys.argv[3:]
        assert jars, "brak jarow"
        for j in jars:
            assert j.startswith("/system/"), "sciezka musi byc absolutna /system/...: " + j
        blob = build(jars)
        # samoweryfikacja 1: własny dekoder
        dec = decode(blob)
        assert [p for p, _ in dec] == jars, dec
        assert all(c == BOOTCLASSPATH for _, c in dec), dec
        # samoweryfikacja 2: krzyżowa z biblioteką protobuf (jesli dostepna)
        try:
            from google.protobuf import descriptor_pb2, descriptor_pool, message_factory
            fdp = descriptor_pb2.FileDescriptorProto()
            fdp.name = "classpaths.proto"
            fdp.syntax = "proto3"
            fdp.package = ""
            fdp.enum_type.add(name="Classpath", value=[
                descriptor_pb2.EnumValueDescriptorProto(name=n, number=v)
                for n, v in [("UNKNOWN", 0), ("BOOTCLASSPATH", 1),
                             ("SYSTEMSERVERCLASSPATH", 2), ("DEX2OATBOOTCLASSPATH", 3),
                             ("STANDALONE_SYSTEMSERVER_JARS", 4)]])
            jar = fdp.message_type.add(name="Jar")
            jar.field.add(name="path", number=1, label=1,
                          type=descriptor_pb2.FieldDescriptorProto.TYPE_STRING)
            jar.field.add(name="classpath", number=2, label=1,
                          type=descriptor_pb2.FieldDescriptorProto.TYPE_ENUM,
                          type_name="Classpath")
            top = fdp.message_type.add(name="ExportedClasspathsJars")
            top.field.add(name="jars", number=1, label=3,
                          type=descriptor_pb2.FieldDescriptorProto.TYPE_MESSAGE,
                          type_name="Jar")
            pool = descriptor_pool.DescriptorPool()
            pool.Add(fdp)
            msg = message_factory.GetMessageClass(
                pool.FindMessageTypeByName("ExportedClasspathsJars"))()
            msg.ParseFromString(blob)
            assert [j.path for j in msg.jars] == jars
            assert all(j.classpath == 1 for j in msg.jars)
            print("protobuf cross-check: OK (%d jarow)" % len(msg.jars))
        except ImportError:
            print("protobuf cross-check: pominiety (brak biblioteki)")
        with open(out, "wb") as fh:
            fh.write(blob)
        print("bootclasspath.pb: %d B, %d jarow:" % (len(blob), len(jars)))
        for j in jars:
            print("  +", j)
    elif mode == "verify":
        path, jars = sys.argv[2], sys.argv[3:]
        blob = open(path, "rb").read()
        dec = decode(blob)
        assert [p for p, _ in dec] == jars, "rozjazd: %r != %r" % (dec, jars)
        assert all(c == BOOTCLASSPATH for _, c in dec)
        print("verify OK: %d jarow na BOOTCLASSPATH" % len(dec))
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
