#!/bin/bash
#
# This script uses separate input egs directory for each language as input,
# to generate egs.*.scp files in multilingual egs directory
# where the scp line points to the original archive for each egs directory.
# $megs/egs.*.scp is randomized w.r.t language id.
#
# Also this script generates egs.JOB.scp, output.JOB.scp and weight.JOB.scp,
# where output file contains language-id for each example
# and weight file contains weights for scaling output posterior
# for each example w.r.t input language.
#
# Begin configuration section.
cmd=run.pl
minibatch_size=512      # multiple of actual minibatch size used during training.
num_jobs=10             # helps for better randomness across languages
                        # per archive.
samples_per_iter=400000 # this is the target number of egs in each archive of egs
                        # (prior to merging egs).  We probably should have called
                        # it egs_per_iter. This is just a guideline; it will pick
                        # a number that divides the number of samples in the
                        # entire data.
stage=0

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

num_langs=$1

shift 1
args=("$@")
echo num_args = ${#args[@]}
megs_dir=${args[-1]} # multilingual directory
mkdir -p $megs_dir
mkdir -p $megs_dir/info
if [ ${#args[@]} != $[$num_langs+1] ]; then
  echo "$0: num of input example dirs provided is not compatible with num_langs $num_langs."
  echo "Usage:$0 [opts] <num-input-langs,N> <lang1-egs-dir> ...<langN-egs-dir> <multilingual-egs-dir>"
  echo "Usage:$0 [opts] 2 exp/lang1/egs exp/lang2/egs exp/multi/egs"
  exit 1;
fi

required="egs.scp combine.egs.scp train_diagnostic.egs.scp valid_diagnostic.egs.scp"
train_scp_list=
train_diagnostic_scp_list=
valid_diagnostic_scp_list=
combine_scp_list=

# read paramter from different $egs_dir[lang]/info
# to write in multilingual egs_dir

check_params="info/feat_dim info/ivector_dim info/left_context info/right_context info/frames_per_eg cmvn_opts"
for param in $check_params; do
  cat ${args[0]}/$param > $megs_dir/$param || exit 1;
done
cat ${args[0]}/cmvn_opts > $megs_dir/cmvn_opts || exit 1;
for lang in $(seq 0 $[$num_langs-1]);do
  multi_egs_dir[$lang]=${args[$lang]}
  for f in $required; do
    if [ ! -f ${multi_egs_dir[$lang]}/$f ]; then
      echo "$0: no such a file ${multi_egs_dir[$lang]}/$f." && exit 1;
    fi
  done
  train_scp_list="$train_scp_list ${args[$lang]}/egs.scp"
  train_diagnostic_scp_list="$train_diagnostic_scp_list ${args[$lang]}/train_diagnostic.egs.scp"
  valid_diagnostic_scp_list="$valid_diagnostic_scp_list ${args[$lang]}/valid_diagnostic.egs.scp"
  combine_scp_list="$combine_scp_list ${args[$lang]}/combine.egs.scp"

  # check parameter dimension to be the same in all egs dirs
  for f in $check_params; do
    f1=`cat $megs_dir/$f`;
    f2=`cat ${multi_egs_dir[$lang]}/$f`;
    if [ "$f1" != "$f2" ]  ; then
      echo "$0: mismatch for $f for $megs_dir vs. ${multi_egs_dir[$lang]}($f1 vs. $f2)."
      exit 1;
    fi
  done
done

if [ $stage -le 0 ]; then
  echo "$0: allocating multilingual examples for training."
  # Generate egs.*.scp for multilingual setup.
  $cmd $megs_dir/log/allocate_multilingual_examples_train.log \
  python steps/nnet3/multilingual/allocate_multilingual_examples.py \
      --minibatch-size $minibatch_size \
      --samples-per-iter $samples_per_iter \
      $num_langs "$train_scp_list" $megs_dir || exit 1;
fi

if [ $stage -le 1 ]; then
  echo "$0: combine combine.egs.scp examples from all langs in $megs_dir/combine.egs.scp."
  # Generate combine.egs.scp for multilingual setup.
  $cmd $megs_dir/log/allocate_multilingual_examples_combine.log \
  python steps/nnet3/multilingual/allocate_multilingual_examples.py \
      --random-lang false \
      --max-archives 1 --num-jobs 1 \
      --minibatch-size $minibatch_size \
      --prefix "combine." \
      $num_langs "$combine_scp_list" $megs_dir || exit 1;

  echo "$0: combine train_diagnostic.egs.scp examples from all langs in $megs_dir/train_diagnostic.egs.scp."
  # Generate train_diagnostic.egs.scp for multilingual setup.
  $cmd $megs_dir/log/allocate_multilingual_examples_train_diagnostic.log \
  python steps/nnet3/multilingual/allocate_multilingual_examples.py \
      --random-lang false \
      --max-archives 1 --num-jobs 1 \
      --minibatch-size $minibatch_size \
      --prefix "train_diagnostic." \
      $num_langs "$train_diagnostic_scp_list" $megs_dir || exit 1;


  echo "$0: combine valid_diagnostic.egs.scp examples from all langs in $megs_dir/valid_diagnostic.egs.scp."
  # Generate valid_diagnostic.egs.scp for multilingual setup.
  $cmd $megs_dir/log/allocate_multilingual_examples_valid_diagnostic.log \
  python steps/nnet3/multilingual/allocate_multilingual_examples.py \
      --random-lang false --max-archives 1 --num-jobs 1\
      --minibatch-size $minibatch_size \
      --prefix "valid_diagnostic." \
      $num_langs "$valid_diagnostic_scp_list" $megs_dir || exit 1;

fi
echo $cmvn_opts > $megs_dir/cmvn_opts || exit 1; # caution: the top-level nnet training
                                                 # script should copy this to its
                                                 # own dir.
echo "$0: Finished preparing multilingual training example."
