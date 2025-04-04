#!/usr/bin/env ruby

require File.expand_path('../../config/environment', __dir__)
require 'solid_queue/cli'

cli = SolidQueue::CLI.new
cli.start(['start', 'worker'])