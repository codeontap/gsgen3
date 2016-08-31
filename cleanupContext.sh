#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi

# Context cleanup is only done from the script that set the context
if [[ -z "${GSGEN_CONTEXT_DEFINED_LOCAL}" ]]; then exit; fi

if [[ (-z "${GSGEN_DEBUG}") && (-n "${ROOT_DIR}") ]]; then
    find ${ROOT_DIR} -name "composite_*" -delete
    find ${ROOT_DIR} -name "STATUS.txt" -delete
    find ${ROOT_DIR} -name "stripped_*" -delete
    find ${ROOT_DIR} -name "temp_*" -delete
    find ${ROOT_DIR} -name "ciphertext*" -delete
fi

