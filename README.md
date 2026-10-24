# jp-ime-keyboard-layout

Windows script that changes the keyboard layout the Japanese IME uses underneath, so accents and dead keys work in its alphanumeric mode (typing Latin letters without leaving the IME). The default is Brazilian ABNT2, but it takes other layouts too.

## Why

Windows only offers two layouts for the Japanese IME: English (101/102 keys) and Japanese (106/109 keys). On an ABNT2 keyboard, `ç`, `´` and `~` stop working while the IME is on, and the same goes for any other layout with dead keys or extra letters.

## How it works

The Japanese keyboard layout (`KBDJPN.DLL`) is just a middleman. It reads the value below and loads whatever layout DLL it names:

```text
HKLM\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters
  "LayerDriver JPN" (REG_SZ)
```

Windows only ever sets it to `kbd101.dll` (English) or `kbd106.dll` (Japanese). The script points it to another layout DLL, like `KBDBR.DLL` for ABNT2. This works for Microsoft IME and also for Mozc and Google Japanese Input on Windows.

## Usage

Download [`jp-ime-layout.cmd`](jp-ime-layout.cmd) and double-click it. It asks for administrator rights through UAC and applies ABNT2. The change only takes effect after you sign out and back in (or restart).

From the Command Prompt:

```text
jp-ime-layout.cmd                    use ABNT2
jp-ime-layout.cmd --layout us-intl   use US International
jp-ime-layout.cmd --undo             back to the original
jp-ime-layout.cmd --hide-keyboard    leave only the Japanese IME
```

| Option | Description |
| --- | --- |
| *(none)*, `--apply` | Apply a layout (default: `abnt2`) |
| `--layout NAME`, `-l NAME` | Layout to use: a name from [Layouts](#layouts) or the file name of any layout DLL in `System32`, like `kbdca.dll`. With `--undo`, restores to this layout instead |
| `--status`, `-s` | Show the current value |
| `--list` | List the layout names |
| `--undo`, `--revert`, `-u` | Restore the original value |
| `--hide-keyboard` | Leave only the Japanese IME for this user (see [Hiding the other keyboard](#hiding-the-other-keyboard)) |
| `--show-keyboard` | Bring the other languages' keyboards back |
| `--no-pause` | Don't wait for a key press at the end |
| `--help`, `-h`, `/?` | Show all options |

Applying and undoing need administrator rights (the script asks via UAC). `--status`, `--list`, `--hide-keyboard` and `--show-keyboard` don't.

## Layouts

| Name | DLL | Layout |
| --- | --- | --- |
| `abnt2` | `KBDBR.DLL` | Portuguese (Brazil, ABNT2) |
| `pt` | `kbdpo.dll` | Portuguese (Portugal) |
| `us` | `kbdus.dll` | US |
| `us-intl` | `KBDUSX.DLL` | US International |
| `uk` | `kbduk.dll` | United Kingdom |
| `es` | `kbdsp.dll` | Spanish |
| `latam` | `kbdla.dll` | Latin American Spanish |
| `de` | `kbdgr.dll` | German |
| `fr` | `kbdfr.dll` | French |
| `it` | `kbdit.dll` | Italian |
| `dvorak` | `kbddv.dll` | US Dvorak |
| `en101` | `kbd101.dll` | English 101/102 keys (Windows option) |
| `jp106` | `kbd106.dll` | Japanese 106/109 keys (Windows option) |

## Backup and undo

Before the first change, the original value is saved once in `%ProgramData%\JpImeLayout\` (`original.txt`, plus `original.reg` with an export of the whole key). Every change is logged to `log.txt` in the same folder.

`--undo` puts the saved value back. If nothing was saved, it falls back to `kbd101.dll` (English 101/102 keys). On a Japanese 106/109 keyboard, use `--undo --layout jp106`.

## Hiding the other keyboard

With ABNT2 under the IME, the separate Portuguese keyboard is no longer needed, but Windows 11 doesn't let you remove the keyboard of the display language and adds it back if you clear it. `--hide-keyboard` keeps the language and its spell checker and, for the current user:

- makes the Japanese IME the default input method (`Set-WinDefaultInputMethodOverride` with the first input method of the Japanese language);
- leaves only Japanese in `HKCU\Keyboard Layout\Preload`.

`--show-keyboard` removes the override and gives each language without a keyboard its default one (`0416:00000416` for pt-BR). Both take effect after you sign out and back in. Changing the languages in Settings may bring the keyboard back; run `--hide-keyboard` again.

## Caveats

- Windows rewrites the value if you change "Hardware keyboard layout" in the Japanese language options, and a major Windows update may reset it. Check with `--status` and run the script again.
- Alt + the key left of `1`, the shortcut that turns the IME on and off, keeps working on ABNT2 and the US layouts, but may break on others, like German and French. If that happens, set another IME on/off key in the Microsoft IME settings (Key and touch customization).

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | OK |
| `1` | Registry write failed |
| `2` | Bad arguments |
| `3` | Layout DLL not found |
| `4` | Japanese input not installed (`--hide-keyboard`) |
| `5` | Could not get administrator rights |
| `1223` | UAC prompt declined |
