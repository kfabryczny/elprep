#!/usr/bin/env python

# Example script for using elPrep split/merge tools.  

import sys
import subprocess
import os
import time
import elprep_io_wrapper
import operator

# actual script

def append_cmd(cmd1, cmd2):
  return cmd1 + " " + cmd2

def elprep_sfm_gnupar ():
  # set up directories for intermediate results
  file_in = sys.argv[1]
  file_out = sys.argv[2]
  input = os.path.basename(file_in)
  output_prefix, output_extension = os.path.splitext(input)
  stamp = str(time.time())
  split_dir = os.path.join(os.getcwd(), "temp-" + stamp + os.sep)
  result_dir = os.path.join(os.getcwd(), "temp-processed-" + stamp + os.sep)
  os.mkdir(split_dir)
  os.mkdir(result_dir)
  # split command
  nr_of_threads_opt = elprep_io_wrapper.cmd_option('--nr-of-threads', sys.argv)
  elprep_io_wrapper.cmd_wrap_input(["elprep", "split"], file_in, split_dir, ["--output-prefix", output_prefix, "--output-type", "sam"] + nr_of_threads_opt)
  spread_file = os.path.join(split_dir, output_prefix + "-spread.sam")
  splits_path = os.path.join(split_dir, "splits" + os.sep)
  # gnu parallel command
  nr_of_jobs_opt = elprep_io_wrapper.cmd_option('--nr-of-jobs', sys.argv)
  read_group_string = elprep_io_wrapper.cmd_option('--replace-read-group', sys.argv)
  given_cmd_opts = elprep_io_wrapper.remove_cmd_option(sys.argv[3:], '--nr-of-jobs')
  cmd_opts = given_cmd_opts
  if read_group_string:
    cmd_opts = elprep_io_wrapper.remove_cmd_option(cmd_opts, '--replace-read-group') 
    cmd_opts = cmd_opts + ['--replace-read-group', '\"' + read_group_string[1] + '\"']
  cmd_opts = cmd_opts + ['--split-file']
  cmd_list = ["elprep"]
  elprep_cmd = '\'' + reduce(append_cmd, cmd_list + ['{}', result_dir + '{/.}.sam' ] + cmd_opts) + '\''
  gnu_cmd = 'parallel --gnu -j ' + str(nr_of_jobs_opt[1]) + ' ' + elprep_cmd + ' ::: ' + splits_path + '*.sam'
  subprocess.check_call(gnu_cmd, shell=True)
  # command for spread file
  spread_out_file = os.path.join(result_dir, output_prefix + "-spread.sam")
  elprep_io_wrapper.cmd_wrap_io(["elprep"], spread_file, spread_out_file , given_cmd_opts)
  # merge command
  elprep_io_wrapper.cmd_wrap_output(["elprep", "merge"], result_dir, file_out, nr_of_threads_opt)
  # remove directories for intermediate results
  for root, dirs, files in os.walk(splits_path):
    for file in files:
      ffile = os.path.join(root, file)
      os.remove(ffile)
  os.rmdir(splits_path)
  os.remove(spread_file)
  os.rmdir(split_dir)
  for root, dirs, files in os.walk(result_dir):
    for file in files:
      ffile = os.path.join(root, file)
      os.remove(ffile)
  os.rmdir(result_dir)

elprep_sfm_gnupar()
