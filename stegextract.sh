#!/usr/bin/env bash

exec 6>&1

if [ $# -eq 0 ]; then
  echo "Usage: stegextract <file> [options]"
  echo "stegextract -h for help"
	exit 0
fi

while (( "$#" )); do
  case "$1" in
    -h|--help)
      echo "Extract hidden data from images"
      echo " "
      echo "Usage: stegextract <file> [options]"
      echo "-h, --help                Print this and exit"
      echo "-o, --outfile             Specify an outfile"
      echo "-a, --analyze             Perform a deep analysis of embedded files"
      echo "-s, --strings             Extract strings from file"
      echo "-q, --quiet               Do not output to stdout"
      echo "--force-format            Force this image format instead of detecting"
      exit 0
			;;
    "-o"|"--outfile")
      outfile=$2
      shift 2
      ;;
    "--force-format")
      ext=$2
      shift 2
      ;;
    "-a"|"--analyze") # Analyze file hexdump for embedded files
      analyze="true"
      shift 1
      ;;
    "-s"|"--strings")
      get_strings="true"
      shift 1
      ;;
    "-q"|"--quiet")
      exec > /dev/null
      shift 1
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      image="$1"
      stripped=${image%.*}
      shift
      ;;
  esac
done

file_type=""

jpg_start="ffd8"
jpg_end="ff d9"

png_start="8950 4e47 0d0a 1a0a"
png_end="49 45 4e 44 ae 42 60 82"

gif_start="4749 4638 3961"
gif_end="00 3b"

if [ ! -f $image ]; then
  echo "$0: File $image not found."
  exit 1
fi

if [ -z ${outfile+x} ]; then
 outfile=$stripped"_dumps";
fi

extract_trailing()  {
	curr=${@:1}
	xxd -c1 -p $image | tr "\n" " " | sed -n -e "s/.*\( $curr \)\(.*\).*/\2/p" | xxd -r -p > $outfile
}

jpeg() {
	file_type="jpg"
	# Grab everything after 0xFF 0xD9
	echo "Detected image format: JPG"
	extract_trailing $jpg_end
}

png() {
	file_type="png"
	# Grab everything after "IEND.B`" chunk
	echo "Detected image format: PNG"
	extract_trailing $png_end
}

gif() {
	file_type="gif"
	# Grab everything after "0x00 0x3B"
	echo "Detected image format: GIF"
	extract_trailing $gif_end
}

extract_embedded() {
	curr_ext="$1"
	magic=${@:2}
	magic_no_ws=$(echo -e "$magic" | tr -d '[:space:]')
	located=$(xxd -ps -c100 $image | grep  $magic_no_ws)
	if [[ $located ]]; then
		upper_ext=$(echo "$curr_ext" | tr /a-z/ /A-Z/)
		echo "Found embedded: $upper_ext"
		echo $magic | xxd -r -p > $stripped.$curr_ext
		xxd -c1 -p $image | tr "\n" " " | sed -n -e "s/.*\( $magic \)\(.*\).*/\2/p" | xxd -r -p >> $stripped.$curr_ext
	fi
}

analysis() {
	echo "Performing deep analysis"
	# TODO: add TIFF, tar, gzip, bz, 7z...
	extensions=("png" "jpg" "gif" "zip" "rar")
	for i in "${extensions[@]}"; do
		# Look for magic numbers in file except for the already detected image type
		if [ $i != $file_type ]; then
			case "$i" in
				"png")
					extract_embedded "png" "89 50 4e 47 0d 0a 1a 0a"
					;;
				"jpg")
					extract_embedded "jpg" "ff d8 ff e0"
					;;
				"gif")
					extract_embedded "gif" "47 49 46 38 39 61"
					;;
				"zip")
					extract_embedded "zip" "50 3b 03 04"
					;;
				"rar")
					extract_embedded "rar" "52 61 72 21 1a 07 01 00"
					;;
			esac
		fi
	done
}

if [[ ! -z ${ext+x} ]]; then
	case ${ext,,} in
  # Lazy format detection
	"jpg"|"jpeg")
		jpeg
		;;
	"png")
		png
		;;
	"gif")
		gif
		;;
	*)
		echo "Unsupported image format"
		exit 1
		;;
	esac
else
	# Look for SOI bytes in xxd output to detect image type
	head_hexdump=$(xxd $image 2> /dev/null  | head)
	if [[ $(grep "$png_start" <<< $head_hexdump) ]]; then
		png
	elif [[ $(grep "$jpg_start" <<< $head_hexdump) ]]; then
		jpeg
	elif [[ $(grep "$gif_start" <<< $head_hexdump) ]]; then
		gif
	else
		echo "Unknown or unsupported image format"
		exit 1
	fi
fi

data=$(file $outfile)
data=${data##*:}
result=$(echo $data | head -n1 | sed -e 's/\s.*$//')
if [ $result = "empty" ]; then
	echo "No trailing data found in file"
	rm $outfile
elif [ $result = "data" ]; then
	echo "Extracted trailing file data: binary data, might contain embedded files."
else
	echo "Extracted trailing file data: $data"
fi

if [[ $analyze ]]; then
	analysis
fi

if [[ $get_strings ]]; then
	echo "Extracting strings..."
	strings -6 $image > $stripped.txt
fi

echo "Done"

exec 1>&6 6>&-