require 'silhouette/setup'

opts = Silhouette::Options.new
opts.import_env
args, file = opts.setup_args

STDERR.puts "Logging profile information to #{file}"
Silhouette.start_profile *args