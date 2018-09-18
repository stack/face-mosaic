#!/usr/bin/env ruby

INPUT_FILE = 'Icon.png'.freeze

SIZES = [
  { size: 512, multiplier: 1 },
  { size: 256, multiplier: 1 },
  { size: 128, multiplier: 1 },
  { size: 32,  multiplier: 1 },
  { size: 16,  multiplier: 1 },
  { size: 512, multiplier: 2 },
  { size: 256, multiplier: 2 },
  { size: 128, multiplier: 2 },
  { size: 32,  multiplier: 2 },
  { size: 16,  multiplier: 2 },
].freeze

SIZES.each do |item|
  name = item[:multiplier] == 1 ? "icon-#{item[:size]}.png" : "icon-#{item[:size]}@#{item[:multiplier]}x.png"
  final_size = item[:size] * item[:multiplier]

  puts "Generating #{name}"

  args = [
    'convert',
    INPUT_FILE,
    '-geometry',
    "#{final_size}x#{final_size}",
    name
  ]

  raise "Failed to run command #{args.join ' '}" unless system(*args)
end
