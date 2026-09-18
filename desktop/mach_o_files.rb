#!/usr/bin/env ruby
# frozen_string_literal: true

module MachOFiles
  MAGICS = [
    0xFEEDFACE, 0xCEFAEDFE, 0xFEEDFACF, 0xCFFAEDFE,
    0xCAFEBABE, 0xBEBAFECA, 0xCAFEBABF, 0xBFBAFECA
  ].freeze

  module_function

  def list(root)
    Dir.glob(File.join(root, "**/*"), File::FNM_DOTMATCH).sort.select do |path|
      File.file?(path) && !File.symlink?(path) && macho?(path)
    end
  end

  def macho?(path)
    MAGICS.include?(File.binread(path, 4).unpack1("N"))
  rescue EOFError
    false
  end
end

puts MachOFiles.list(ARGV.fetch(0)) if $PROGRAM_NAME == __FILE__
