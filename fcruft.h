/* fcruft.h --- sometimes kids make messes for others to clean up

   Copyright (C) 2004 Thien-Thi Nguyen

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software Foundation,
   Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA  */

/* It is only w/ great patience that this file exists, and w/o ranting.

   This file is included in the AH_BOTTOM block (see configure.in).
   The tests for each HAVE_ symbol are defined in acinclude.m4 under
   the autoconf macro AC_GUILE_PG_FCOMPAT.  */

#ifdef HAVE_SCM_GC_PROTECT_OBJECT
#define scm_protect_object(x)  (scm_gc_protect_object (x))
#endif

#ifndef HAVE_SCM_OUTPORTP
#define SCM_OUTPORTP(x)  (SCM_OUTPUT_PORT_P (x))
#endif

/* fcruft.h ends here */