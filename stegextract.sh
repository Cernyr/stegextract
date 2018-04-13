#!/usr/bin/env bash


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
      echo "--force-format            Force this image format instead of detecting"
      echo "-o, --outfile             Specify an outfile"
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

pk_start="50 3b 03 04"

if [ ! -f $image ]; then
  echo "$0: File $image not found."
  exit 1
fi

if [ -z ${outfile+x} ]; then
 outfile=${image%.*}"_dumps";
fi

extract()  {
	curr=${@:1}
	xxd -c1 -p $image | tr "\n" " " | sed -n -e "s/.*\( $curr \)\(.*\).*/\2/p" | xxd -r -p > $outfile
}

jpeg() {
	file_type="jpg"
	# Grab everything after 0xFF 0xD9
	echo "Detected image format: JPG"
	extract $jpg_end
}

png() {
	file_type="png"
	# Grab everything after "IEND.B`" chunk
	echo "Detected image format: PNG"
	extract $png_end
}

gif() {
	file_type="gif"
	# Grab everything after "0x00 0x3B"
	echo "Detected image format: GIF"
	extract $gif_end
}

#further_analysis() {
# Assign to var:
# PNG Match: xxd -c1 -p happypassover.jpg | tr "\n" " " | sed -n 's/.*\(89 50 4e 47 0d 0a 1a 0a\).*/\1/p'
# Write magic number to file + trailing
#
#}

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
	echo "No hidden data found in file"
	rm $outfile
	exit 1
else
	echo "Extracted hidden file data: "$data
	echo "Extracting strings..."
	strings -6 $image > $outfile.txt
	echo "Done"
fi



# TODO: Consider adding Rar!.. & PK.. file signatures lookup and extraction
# TODO: Consider image within image lookup and extraction