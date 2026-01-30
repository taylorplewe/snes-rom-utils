# snestils
A CLI that encompasses a suite of utilities for working with Super Nintendo/Super Famicom ROM files. I really wanted to just have one tool I use for all the different things you have to do to a ROM to make it runnable on real hardware. Nick from MouseBiteLabs has written [some great instructions on how to do so](https://mousebitelabs.com/2017/09/14/how-to-make-a-snes-reproduction-cartridge/), but it requires the use of at least four different (somewhat jank/sketchy) tools from the internet to do all the different things.

## Utilities
| Name | Description |
| - | - |
| `fix-checksum` | Fix the internal ROM's checksum and complement |
| `split` | Split the ROM file into different size chunks, for writing to various (E)EPROMs |
| `patch` | Apply a patch file to a ROM. Supported patch types |

### Supported patch file types
- IPS
- UPS
