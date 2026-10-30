<?php

namespace App\Services;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Str;

/**
 * Archivos subidos (fotos e iconos), guardados dentro de public/ para que el
 * servidor web los sirva directamente.
 */
class Uploads
{
    /**
     * Guarda el archivo y devuelve su ruta relativa a public/.
     */
    /**
     * @param string|null $extension extensión a usar (si no, la que se deduce del contenido)
     */
    public function store(UploadedFile $file, string $folder, ?string $extension = null): string
    {
        $relativeFolder = config('mitransporte.uploads_directory').'/'.$folder;
        $name = Str::random(32).'.'.strtolower($extension ?: ($file->guessExtension() ?: $file->getClientOriginalExtension()));

        $file->move($this->publicPath($relativeFolder), $name);

        return $relativeFolder.'/'.$name;
    }

    public function delete(?string $relativePath): void
    {
        if ($relativePath && is_file($this->publicPath($relativePath))) {
            unlink($this->publicPath($relativePath));
        }
    }

    public function publicPath(string $relativePath): string
    {
        return base_path('public/'.$relativePath);
    }
}
