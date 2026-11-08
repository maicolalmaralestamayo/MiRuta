<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ServerKey extends Model
{
    protected $fillable = ['purpose', 'public_key', 'private_key_encrypted'];

    protected $hidden = ['private_key_encrypted'];
}
