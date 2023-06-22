#!/bin/bash -e

# source setup variables
# if copy/pasting these commands, need to run from this directory
if [ -n "${PAWSEY_CLUSTER}" ] && [ -z ${SYSTEM+x} ]; then
    SYSTEM="$PAWSEY_CLUSTER"
fi

if [ -z ${SYSTEM+x} ]; then
    echo "The 'SYSTEM' variable is not set. Please specify the system you want to
    build Spack for."
    exit 1
fi

PAWSEY_SPACK_CONFIG_REPO=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )
. "${PAWSEY_SPACK_CONFIG_REPO}/systems/${SYSTEM}/settings.sh"

# This script creates end user singularity modules, starting from the Spack one
# For each version:
# 1. creates several modules each setting different default behaviour:
#    A. singularity/x.x.x-mpi : injects all necessary libraries to run MPI, binds filesystems /scratch, /software, etc
#    B. singularity/x.x.x-nompi : binds filesystems, also sets LD path based on currenty LD path 
#    C. singularity/x.x.x-askap : like MPI but also addes /askapbuffer and also adds slurm related bind mounts 
#    D. singularity/x.x.x-nohost : nothing from the host is injected, does mount file systems
#    E. singularity/x.x.x-slurm : like nompi but also mounts directories related to running slurm in a container
# 2. hides Spack module in {spack modules}/{arch}/{compiler}
#    - to avoid confusion

# define source (Spack) and destination (Pawsey) directories for Singularity
src_dir="${INSTALL_PREFIX}/modules/${cpu_arch}/gcc/${gcc_version}/utilities/${singularity_name}"
dst_dir="${INSTALL_PREFIX}/${singularity_symlink_module_dir}"

# ensure destination directory exists
mkdir -p ${dst_dir}
# remove old pawsey singularity modules
rm -f ${dst_dir}/*.lua

for version in $( ls ${src_dir}/*.lua ${src_dir}/.*.lua 2>/dev/null ) ; do
  version="${version##*/}"
  version="${version#.}"
  #2. hide Spack module
  if [ -e ${src_dir}/${version} ] ; then
    mv ${src_dir}/${version}.lua ${src_dir}/.${version}
  fi
  # 1.C singularity-askap is just the original module
  cp -p ${src_dir}/.${version} ${dst_dir}/${version}-askap.lua
  # 1.A singularity does not bind mount /askapbuffer nor add slurm
  sed \
    -e '/singularity_bindpath *=/ s;/askapbuffer;;g' \
    -e '/^-- add SLURM START/,/^-- add SLURM END/{/^-- add SLURM START/!{/^-- add SLURM END/!d}}' \
    ${src_dir}/.${version} > ${dst_dir}/${version}-mpi.lua
  # 1.B singularity does not add any mpi related stuff
  sed \
    -e '/singularity_bindpath *=/ s;/askapbuffer;;g' \
    -e '/^-- add MPI START/,/^-- add MPI END/{/^-- add MPI START/!{/^-- add MPI END/!d}}' \
    -e '/^-- add SLURM START/,/^-- add SLURM END/{/^-- add SLURM START/!{/^-- add SLURM END/!d}}' \
    ${src_dir}/.${version} > ${dst_dir}/${version}-nompi.lua
  # 1.D singularity does not add any thing at all from host 
  sed \
    -e '/singularity_bindpath *=/ s;/askapbuffer;;g' \
    -e '/^-- add MPI START/,/^-- add MPI END/{/^-- add MPI START/!{/^ add MPI END/!d}}' \
    -e '/^-- add SLURM START/,/^-- add SLURM END/{/^-- add SLURM START/!{/^-- add SLURM END/!d}}' \
    -e '/^-- add CRAY_PATHS START/,/^-- add CRAY_PATHS END/{/^-- add CRAY_PATHS START/!{/^-- add CRAY_PATHS END/!d}}' \
    -e '/^-- add CURRENT_HOST_LD_PATH START/,/^-- add CURRENT_HOST_LD_PATH END/{/^-- add CURRENT_HOST_LD_PATH START/!{/^-- add CURRENT_HOST_LD_PATH END/!d}}' \
    ${src_dir}/.${version} > ${dst_dir}/${version}-nohost.lua 
  # 1.B singularity does not add any mpi related stuff
  sed \
    -e '/singularity_bindpath *=/ s;/askapbuffer;;g' \
    -e '/^-- add MPI START/,/^-- add MPI END/{/^-- add MPI START/!{/^-- add MPI END/!d}}' \
    ${src_dir}/.${version} > ${dst_dir}/${version}-slurm.lua
done
