<?php

namespace Tests\Feature;

use App\Models\Entity;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

/**
 * Fotos e imágenes (multipart/form-data, respuesta JSON:API).
 */
class UploadsTest extends TestCase
{
    private function upload(User $who, string $uri, string $field)
    {
        return $this->call('POST', $uri, [], [], [$field => UploadedFile::fake()->image('foto.jpg', 50, 50)], [
            'HTTP_ACCEPT' => 'application/vnd.api+json',
            'HTTP_AUTHORIZATION' => 'Bearer '.$this->tokenFor($who),
            'CONTENT_TYPE' => 'multipart/form-data; boundary=x',
        ]);
    }

    public function test_foto_de_perfil_e_imagen_de_entidad(): void
    {
        $user = $this->createUser();
        $admin = $this->createAdmin();
        $entity = $this->createEntity();

        $url = $this->upload($user, '/api/v1/me/photo', 'photo')->assertOk()->json('data.attributes.photoUrl');
        $this->assertStringContainsString('/uploads/photos/', $url);
        $this->jsonApiAs($user, 'DELETE', '/api/v1/me/photo')->assertNoContent();
        $this->assertNull(User::find($user->id)->photo_path);

        $this->upload($user, "/api/v1/entities/{$entity->id}/image", 'image')->assertForbidden();
        $this->upload($admin, "/api/v1/entities/{$entity->id}/image", 'image')->assertOk()->assertJsonPath('data.type', 'entities');
        $path = Entity::find($entity->id)->image_path;
        $this->assertFileExists(public_path($path));
        $this->jsonApiAs($admin, 'DELETE', "/api/v1/entities/{$entity->id}/image")->assertNoContent();
        $this->assertFileDoesNotExist(public_path($path));
    }
}
