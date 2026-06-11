/*
 * fishhook - Facebook's library for dynamically rebinding symbols
 * in Mach-O binaries running on iOS.
 *
 * Copyright (c) 2013, Facebook, Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *   * Redistributions of source code must retain the above copyright notice.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice in lists of conditions and the following disclaimer.
 *   * Neither the name Facebook nor the names of its contributors may be
 *     used to endorse or promote products derived from this software without
 *     specific prior written permission.
 */

#ifndef Fishhook_h
#define Fishhook_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

struct rebinding_entry {
    struct rebinding *rebindings;
    size_t rebindings_nel;
    struct rebinding_entry *next;
};

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel);

int rebind_symbols_image(void *header,
                         intptr_t slide,
                         struct rebinding rebindings[],
                         size_t rebindings_nel);

#ifdef __cplusplus
}
#endif

#endif
