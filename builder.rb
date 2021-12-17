#!/usr/bin/env ruby
# builder.rb - generate k8s.yml in manifests/

require 'yaml'

command = 'bundle exec kuby -e production resources'

# from: https://coderedirect.com/questions/353836/fork-child-process-with-timeout-and-capture-output
array = []

# stdout, stderr pipes
rout, wout = IO.pipe
rerr, werr = IO.pipe

pid = Process.spawn(command, :out => wout, :err => werr)
_, status = Process.wait2(pid)

# close write ends so we could read them
wout.close
werr.close

@stdout = rout.readlines.join
@stderr = rerr.readlines.join

# dispose the read ends of the pipes
rout.close
rerr.close

@last_exit_status = status.exitstatus

if 0 == @last_exit_status && @stderr == ""
  YAML.load_stream(@stdout) { |doc| array << doc }

  # Filter any secrets and regular manifests into separate partitions
  secrets, manifests = array.partition { |x| x["kind"] == "Secret" }

  # If it is a Secret, it needs special handling with SOPS for
  # encryption (or we should throw it away, for now)
  secrets = ''

  # If it is any other resource, it can go in manifests/k8s.yml
  # and be part of the base deployment
  manifest_yaml_document_text = manifests.map(&:to_yaml).join

  # Write the manifest file out
  File.open('manifests/k8s.yml', 'w') { |file| file.write(manifest_yaml_document_text) }
else
  puts @stderr
  Kernel.exit(@last_exit_status)
end
