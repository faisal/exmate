#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'

load File.join(__dir__, 'rave')

# Builds the minimal `archs` hash shape Target.include_dir expects, for tests.
module ArchsBuilder
  module_function

  def build(name:, headers: nil, flat_headers: nil)
    target = { name: name, builddir: '$builddir', build: { rules: [] } }
    target[:headers]      = headers      if headers
    target[:flat_headers] = flat_headers if flat_headers
    { no_arch: target }
  end
end

describe 'Target.include_dir with headers (nested, framework-style includes)' do
  it 'exports the header nested under the target name, and returns the outer include dir' do
    archs = ArchsBuilder.build(name: 'encoding', headers: ['Frameworks/encoding/src/encoding.h'])

    dir = Target.include_dir(archs)
    export_rule = archs[:no_arch][:build][:rules].find { |rule| rule[:name] == 'ExportHeader' }

    assert_equal '$builddir/_Include/encoding', dir
    assert_equal 'Frameworks/encoding/src/encoding.h', export_rule[:in]
    assert_equal '$builddir/_Include/encoding/encoding/encoding.h', export_rule[:out]
  end
end

describe 'Target.include_dir with flat_headers (flat, C-library-style includes)' do
  it 'exports the header directly under the include dir, so a plain #include <oniguruma.h> resolves' do
    archs = ArchsBuilder.build(name: 'Onigmo', flat_headers: ['vendor/Onigmo/vendor/src/oniguruma.h'])

    dir = Target.include_dir(archs)
    export_rule = archs[:no_arch][:build][:rules].find { |rule| rule[:name] == 'ExportHeader' }

    assert_equal '$builddir/_Include/Onigmo', dir
    assert_equal 'vendor/Onigmo/vendor/src/oniguruma.h', export_rule[:in]
    assert_equal File.join(dir, 'oniguruma.h'), export_rule[:out]
  end
end

describe 'Target.include_dir with neither headers nor flat_headers' do
  it 'returns nil' do
    archs = ArchsBuilder.build(name: 'kj')

    assert_nil Target.include_dir(archs)
  end
end
