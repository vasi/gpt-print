#!/usr/bin/ruby
# (C) 2008 Dave Vasilevsky <dave@vasilevsky.ca>
# Licensing: Simplified BSD License, see LICENSE file
require 'iconv'
require 'yaml'

# Globally unique ID
class GUID
	attr_reader :data
	
	def initialize(ledata) # little-endian raw bytes
		@data = ledata
	end
	
	# printable format
	def to_s
		frags = [4, 2, 2, 2, 6]
		reverse = 3 # byte reversal on first 3 parts
		pos = 0
		
		frags.map do |f|
			p = @data[pos, f]
			p = p.reverse if reverse > 0
			
			reverse -= 1
			pos += f
			
			p.unpack('H*')[0].upcase
		end.join('-')
	end
end

class GPTHeader
	BlockSize = 512
	Magic = "EFI PART"
	Version = "\x00\x00\x01\x00"
	
	attr_reader :entryCount, :entrySize, :entryLBA
	
	def initialize(device)
		@data = IO.read(device, BlockSize, BlockSize)
		@magic = @data[0, Magic.size]
		raise 'Not a GPT partition!' if @magic != Magic
		@version = @data[8, 4]
		raise 'Bad GPT version' if @version != Version
		
		@entryLBA = @data[72, 8].unpack('Q<')[0]
		raise 'Weird LBA' if @entryLBA != 2
		@entryCount = @data[80, 4].unpack('L<')[0]
		@entrySize = @data[84, 4].unpack('L<')[0]
	end
end

class GPTEntry < Struct.new(:entries, :index, :e_size) # index is one-based
	def offset
		e_size * (index - 1)
	end
	
	def type
		GUID.new(entries[offset, 0x10])
	end
	
	def uuid
		GUID.new(entries[offset + 0x10, 0x10])	
	end
	
	def start
		entries[offset + 0x20, 8].unpack('Q<')[0]
	end
	
	def finish
		entries[offset + 0x28, 8].unpack('Q<')[0]
	end
	
	def size
		finish - start + 1 # finish is inclusive
	end
	
	def name
		Iconv.conv('UTF-8', 'UTF-16LE', entries[offset + 0x38, 72]).
			unpack('Z*')[0] # remove trailing nulls
	end
		
	def unused?	# partition is unused if GUID is all zero
		type.data.split('').all? { |x| x == "\0" }
	end
	
	
	def to_s	# YAML output
		first = true
		lines = %w[index type uuid start size name].map do |k|
			v = send(k).to_s
			f, first = first, false
			(f ? '- ' : '  ') + "#{k}: #{v}"	# add '- ' to first line
		end
		lines.join("\n")
	end
	
	def self.entries(device)
		hdr = GPTHeader.new(device)
		data = IO.read(device, hdr.entryCount * hdr.entrySize,
			hdr.entryLBA * GPTHeader::BlockSize)
		(1..hdr.entryCount).map { |i| new(data, i, hdr.entrySize) }
	end
	
	def self.print(device)
		entries(device).each do |e|
			next if e.unused?
			puts e
		end
	end
end

device = ARGV.shift
GPTEntry.print(device)
