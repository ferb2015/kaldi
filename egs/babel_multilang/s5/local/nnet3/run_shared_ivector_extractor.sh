#!/bin/bash

# Copyright 2016 Pegah Ghahremani

# This script used to train iVector extractor shared across different languages
# using input data dir containing training data for multiple languages.
# This script uses the input "{lda_mllt_lang}" language to train lda-mllt model.

. ./cmd.sh
set -e
stage=4
use_flp=false
suffix=       # _sp, to use speed-perturbed data to generate lda+mllt model.
numLeavesMLLT=5500
numGaussMLLT=90000
boost_sil=1.0 # Factor by which to boost silence likelihoods in alignment

[ ! -f ./conf/common_vars.sh ] && echo 'the file conf/common_vars.sh does not exist!' && exit 1;

. conf/common_vars.sh || exit 1;

. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: $0 [options] <lda-mllt-lang> <data-dir> <ivector-extractor-dir>"
  echo "e.g.: $0  102-assamese data/multi/train exp/multi/nnet3"
  exit 1;
fi

lda_mllt_lang=$1 # lda-mllt transform used to train global-ivector
multi_data_dir=$2
global_extractor_dir=$3

langconf=conf/$lda_mllt_lang/lang.conf
[ ! -f $langconf ] && echo 'Language configuration does not exist! Use the configurations in conf/lang/* as a startup' && exit 1
. $langconf || exit 1;

if [ $stage -le 4 ]; then
  # We need to build a small system just because we need the LDA+MLLT transform
  # to train the diag-UBM on top of.  We use --num-iters 13 because after we get
  # the transform (12th iter is the last), any further training is pointless.
  # this decision is based on fisher_english
  mkdir -p exp/$lda_mllt_lang/nnet3
  steps/train_lda_mllt.sh --cmd "$train_cmd" --num-iters 13 \
    --splice-opts "--left-context=3 --right-context=3" \
    --boost-silence $boost_sil \
    $numLeavesMLLT $numGaussMLLT data/$lda_mllt_lang/train${suffix}_hires \
    data/$lda_mllt_lang/lang exp/$lda_mllt_lang/tri5_ali${suffix} exp/$lda_mllt_lang/nnet3/tri3b
fi

if [ $stage -le 5 ]; then
  # To train a diagonal UBM we don't need very much data, so use the smallest subset.
  steps/online/nnet2/train_diag_ubm.sh --cmd "$train_cmd" --nj 200 --num-frames 500000 \
    $multi_data_dir $numGaussUBM exp/$lda_mllt_lang/nnet3/tri3b $global_extractor_dir/diag_ubm
fi

if [ $stage -le 6 ]; then
  # iVector extractors can be sensitive to the amount of data, but this one has a
  # fairly small dim (defaults to 100) so we don't use all of it, we use just the
  # 100k subset (just under half the data).
  steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd" --nj 200 \
    $multi_data_dir  $global_extractor_dir/diag_ubm $global_extractor_dir/extractor || exit 1;
fi
exit 0;
