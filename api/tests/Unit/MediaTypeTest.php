<?php

namespace Tests\Unit;

use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase as PlainTestCase;

use App\JsonApi\MediaType;

class MediaTypeTest extends PlainTestCase
{
    public function testContentType()
    {
        $this->assertTrue(MediaType::isValidContentType('application/vnd.api+json'));
        $this->assertTrue(MediaType::isValidContentType('application/vnd.api+json; ext="https://jsonapi.org/ext/atomic"'));
        $this->assertFalse(MediaType::isValidContentType('application/json'));
        $this->assertFalse(MediaType::isValidContentType('application/vnd.api+json; charset=utf-8'));
        $this->assertFalse(MediaType::isValidContentType(null));
    }

    public function testAccept()
    {
        $this->assertTrue(MediaType::isAcceptable(null));
        $this->assertTrue(MediaType::isAcceptable('*/*'));
        $this->assertTrue(MediaType::isAcceptable('application/vnd.api+json'));
        $this->assertTrue(MediaType::isAcceptable('application/vnd.api+json; charset=utf-8, application/vnd.api+json'));
        $this->assertFalse(MediaType::isAcceptable('application/vnd.api+json; charset=utf-8'));
    }
}
