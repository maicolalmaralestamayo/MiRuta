<?php

namespace App\Support;

/**
 * Lee versionName y versionCode del AndroidManifest.xml (binario) de un APK,
 * sin extensiones de PHP: el APK es un ZIP y el manifiesto, un XML binario de
 * Android (AXML). Así el Administrador no tiene que escribirlos (docs/09 §33).
 */
final class ApkInfo
{
    /**
     * @return array{versionName: ?string, versionCode: ?int}|null null si no se puede leer
     */
    public static function read(string $path): ?array
    {
        $manifest = self::extract($path, 'AndroidManifest.xml');

        return $manifest === null ? null : self::parseManifest($manifest);
    }

    /**
     * Contenido de un archivo dentro de un ZIP (almacenado o comprimido con deflate).
     */
    private static function extract(string $path, string $name): ?string
    {
        $zip = @file_get_contents($path);

        if ($zip === false || strlen($zip) < 22) {
            return null;
        }

        // Fin del directorio central: buscar la firma desde el final.
        $eocd = strrpos($zip, "PK\x05\x06");

        if ($eocd === false) {
            return null;
        }

        $entries = unpack('v', substr($zip, $eocd + 10, 2))[1];
        $offset = unpack('V', substr($zip, $eocd + 16, 4))[1];

        for ($i = 0; $i < $entries; $i++) {
            if (substr($zip, $offset, 4) !== "PK\x01\x02") {
                return null;
            }

            $header = unpack('vmethod/x8/Vcompressed/Vsize/vnameLength/vextraLength/vcommentLength/x8/Vlocal', substr($zip, $offset + 10, 36));
            $entryName = substr($zip, $offset + 46, $header['nameLength']);

            if ($entryName === $name) {
                $local = $header['local'];
                $lengths = unpack('vname/vextra', substr($zip, $local + 26, 4));
                $data = substr($zip, $local + 30 + $lengths['name'] + $lengths['extra'], $header['compressed']);

                if ($header['method'] === 0) {
                    return $data;
                }

                if ($header['method'] === 8) {
                    $inflated = @gzinflate($data);

                    return $inflated === false ? null : $inflated;
                }

                return null;
            }

            $offset += 46 + $header['nameLength'] + $header['extraLength'] + $header['commentLength'];
        }

        return null;
    }

    private static function parseManifest(string $xml): ?array
    {
        if (strlen($xml) < 8 || unpack('v', substr($xml, 0, 2))[1] !== 0x0003) {
            return null;
        }

        $strings = [];
        $position = 8;
        $length = strlen($xml);

        while ($position + 8 <= $length) {
            $chunk = unpack('vtype/vheaderSize/Vsize', substr($xml, $position, 8));

            if ($chunk['size'] < 8) {
                return null;
            }

            if ($chunk['type'] === 0x0001) {
                $strings = self::stringPool(substr($xml, $position, $chunk['size']), $chunk['headerSize']);
            } elseif ($chunk['type'] === 0x0102) {
                $element = unpack('Vns/Vname/vattributeStart/vattributeSize/vattributeCount', substr($xml, $position + 16, 14));
                $tag = isset($strings[$element['name']]) ? $strings[$element['name']] : '';

                if ($tag === 'manifest') {
                    $result = ['versionName' => null, 'versionCode' => null];
                    $start = $position + 16 + $element['attributeStart'];

                    for ($i = 0; $i < $element['attributeCount']; $i++) {
                        $attribute = unpack('Vns/Vname/Vraw/vsize/Cres/Ctype/Vdata', substr($xml, $start + $i * $element['attributeSize'], 20));
                        $attributeName = isset($strings[$attribute['name']]) ? $strings[$attribute['name']] : '';

                        if ($attributeName === 'versionCode') {
                            $result['versionCode'] = $attribute['data'];
                        } elseif ($attributeName === 'versionName') {
                            $index = $attribute['raw'] !== 0xFFFFFFFF ? $attribute['raw'] : $attribute['data'];
                            $result['versionName'] = isset($strings[$index]) ? $strings[$index] : null;
                        }
                    }

                    return $result;
                }
            }

            $position += $chunk['size'];
        }

        return null;
    }

    /**
     * @return string[]
     */
    private static function stringPool(string $chunk, int $headerSize): array
    {
        $header = unpack('Vcount/Vstyles/Vflags/VstringsStart', substr($chunk, 8, 16));
        $utf8 = ($header['flags'] & 0x100) !== 0;
        $strings = [];

        for ($i = 0; $i < $header['count']; $i++) {
            $offset = $header['stringsStart'] + unpack('V', substr($chunk, $headerSize + $i * 4, 4))[1];

            if ($utf8) {
                $offset += (ord($chunk[$offset]) & 0x80) ? 2 : 1; // longitud en UTF-16
                $bytes = ord($chunk[$offset]);
                if ($bytes & 0x80) {
                    $bytes = (($bytes & 0x7F) << 8) | ord($chunk[$offset + 1]);
                    $offset += 2;
                } else {
                    $offset += 1;
                }
                $strings[] = substr($chunk, $offset, $bytes);
            } else {
                $units = unpack('v', substr($chunk, $offset, 2))[1];
                if ($units & 0x8000) {
                    $units = (($units & 0x7FFF) << 16) | unpack('v', substr($chunk, $offset + 2, 2))[1];
                    $offset += 4;
                } else {
                    $offset += 2;
                }
                $strings[] = mb_convert_encoding(substr($chunk, $offset, $units * 2), 'UTF-8', 'UTF-16LE');
            }
        }

        return $strings;
    }
}
