# Third-Party Notices

## smartctl (smartmontools)

`Drive Protector.app` embeds a prebuilt `smartctl` binary from
[smartmontools](https://www.smartmontools.org/) to read SMART data from
disks. smartctl is distributed under the GNU General Public License
(GPL-2.0-or-later, with an exception for linking; see
`https://www.smartmontools.org/` and the COPYING file in the
smartmontools source distribution).

- Version embedded: smartctl 7.5 (2025-04-30 r5714)
- Source: https://github.com/smartmontools/smartmontools/releases
- License: GPL-2.0-or-later — https://www.gnu.org/licenses/old-licenses/gpl-2.0.html

The binary is used as an external helper process invoked at runtime; the
Drive Protector source code in this repository is licensed separately
under the MIT License (see `LICENSE`).
