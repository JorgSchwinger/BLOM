! Copyright (C) 2025  J. Maerz, J. Schwinger, T. Torsvik
!
! This file is part of BLOM/iHAMOCC.
!
! BLOM is free software: you can redistribute it and/or modify it under the
! terms of the GNU Lesser General Public License as published by the Free
! Software Foundation, either version 3 of the License, or (at your option)
! any later version.
!
! BLOM is distributed in the hope that it will be useful, but WITHOUT ANY
! WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
! FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for
! more details.
!
! You should have received a copy of the GNU Lesser General Public License
! along with BLOM. If not, see https://www.gnu.org/licenses/.

module mo_kind

  use mod_types,   only: blom_i1 => i1, blom_i2 => i2, blom_i4 => i4, blom_i8 => i8, &
                         blom_r4 => r4, blom_r8 => r8, blom_char_s, blom_char_m,     &
                         blom_char_l, blom_char_x, blom_char_xx
  use mod_utility, only: fnmlen

  implicit none
  private

  !----------------------------------------------------------------------------
  ! precision/kind constants, default settings
  !----------------------------------------------------------------------------

  integer,parameter :: i1 = blom_i1                   ! 8-bit integer
  integer,parameter :: i2 = blom_i2                   ! 16-bit integer
  integer,parameter :: i4 = blom_i4                   ! 32-bit integer
  integer,parameter :: i8 = blom_i8                   ! 64-bit integer
  integer,parameter :: r4 = blom_r4                   ! 4 byte real
  integer,parameter :: r8 = blom_r8                   ! 8 byte real
  integer,parameter :: HAMOCC_CHAR_S  = blom_char_s   ! short char
  integer,parameter :: HAMOCC_CHAR_M  = blom_char_m   ! mid-sized char
  integer,parameter :: HAMOCC_CHAR_L  = blom_char_l   ! long char
  integer,parameter :: HAMOCC_CHAR_X  = blom_char_x   ! extra-long char
  integer,parameter :: HAMOCC_CHAR_XX = blom_char_xx  ! extra-extra-long char

  ! NOTE: iHAMOCC currently only supports 8-byte real values.
  ! This is mainly related to reading and writing routines in mo_netcdf_bgcrw.F90
  ! where double precision is hard-coded (and which are used in several modules)
  ! (note further that mo_read_rivin.F90 calls a BLOM rw-routine, which may also clash)
  integer,parameter :: bgc_fnmlen = fnmlen            ! default filename length
  integer,parameter :: rp = r8                        ! default real precision
  integer,parameter :: ip = i4                        ! default integer precision

  ! Only expose the default parameters at this stage.
  ! We can revisit this if we see that a larger set of parameters is needed.
  public :: bgc_fnmlen, rp, ip

end module mo_kind
