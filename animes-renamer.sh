#!/bin/bash

SCRIPT_FOLDER=$(dirname $(readlink -f $0))
source $SCRIPT_FOLDER/config.conf
LOG=$LOG_FOLDER/animes/$(date +%Y.%m.%d).log
MATCH_LOG=$LOG_FOLDER/missing-id.log

# function
function get-mal-id () {
jq ".[] | select( .tvdb_id == ${tvdb_id} ) | select( .tvdb_season == 1 ) | select( .tvdb_epoffset == 0 ) | .mal_id" -r $SCRIPT_FOLDER/tmp/list-animes-id.json
}
function get-anilist-id () {
jq ".[] | select( .mal_id == ${mal_id} ) | .anilist_id" -r $SCRIPT_FOLDER/tmp/list-animes-id.json
}
function get-tvdb-id () {
jq ".[] | select( .mal_id == ${mal_id} ) | .tvdb_id" -r $SCRIPT_FOLDER/tmp/list-animes-id.json
}
function get-mal-infos () {
if [ ! -f $SCRIPT_FOLDER/data/animes/$mal_id.json ] 										#check if exist
then
	sleep 0.5
	curl "https://api.jikan.moe/v4/anime/$mal_id" > $SCRIPT_FOLDER/data/animes/$mal_id.json
	sleep 1.5
fi
}
function get-anilist-infos () {
if [ ! -f $SCRIPT_FOLDER/data/animes/title-$mal_id.json ]
then
	sleep 0.5
	curl 'https://graphql.anilist.co/' \
	-X POST \
	-H 'content-type: application/json' \
	--data '{ "query": "{ Media(id: '"$anilist_id"') { title { romaji } } }" }' > $SCRIPT_FOLDER/data/animes/title-$mal_id.json
	sleep 1.5
fi
}
function get-anilist-title () {
jq .data.Media.title.romaji -r $SCRIPT_FOLDER/data/animes/title-$mal_id.json
}
function get-mal-eng-title () {
jq .data.title_english -r $SCRIPT_FOLDER/data/animes/$mal_id.json
}
function get-mal-rating () {
jq .data.score -r $SCRIPT_FOLDER/data/animes/$mal_id.json
}
function get-mal-poster () {
if [ ! -f $POSTERS_FOLDER/$mal_id.jpg ]										#check if exist
then
	sleep 0.5
	mal_poster_url=$(jq .data.images.jpg.large_image_url -r $SCRIPT_FOLDER/data/animes/$mal_id.json)
	curl "$mal_poster_url" > $POSTERS_FOLDER/$mal_id.jpg
	sleep 1.5
else
	postersize=$(du -b $POSTERS_FOLDER/$mal_id.jpg | awk '{ print $1 }')
	if [[ $postersize -lt 10000 ]]
	then
		rm $POSTERS_FOLDER/$mal_id.jpg
		sleep 0.5
		mal_poster_url=$(jq .data.images.jpg.large_image_url -r $SCRIPT_FOLDER/data/animes/$mal_id.json)
		curl "$mal_poster_url" > $POSTERS_FOLDER/$mal_id.jpg
		sleep 1.5
	fi
fi
}
function get-mal-tags () {
(jq '.data.genres  | .[] | .name' -r $SCRIPT_FOLDER/data/animes/$mal_id.json && jq '.data.demographics  | .[] | .name' -r $SCRIPT_FOLDER/data/animes/$mal_id.json) | awk '{print $0}' | paste -s -d, -
}
function get-mal-studios() {
if awk -F"\t" '{print $2}' $SCRIPT_FOLDER/override-ID-animes.tsv | grep -w  $mal_id
then
     line=$(grep -w -n $mal_id $SCRIPT_FOLDER/override-ID-animes.tsv | cut -d : -f 1)
	studio=$(sed -n "${line}p" $SCRIPT_FOLDER/override-ID-animes.tsv | awk -F"\t" '{print $4}')
     if [[ -z "$studio" ]]
	then
          mal_studios=$(jq '.data.studios[0] | [.name]| @tsv' -r $SCRIPT_FOLDER/data/animes/$mal_id.json)
     else
          mal_studios=$(echo "$studio")
     fi
else
	mal_studios=$(jq '.data.studios[0] | [.name]| @tsv' -r $SCRIPT_FOLDER/data/animes/$mal_id.json)
fi
}

# download pmm animes mapping and check if files and folder exist
if [ ! -f $animes_titles ]											#check if metadata files exist and echo first line
then
	echo "metadata:" > $animes_titles
else
	rm $animes_titles
	echo "metadata:" > $animes_titles
fi
if [ ! -d $SCRIPT_FOLDER/data ]										#check if exist and create folder for json data
then
	mkdir $SCRIPT_FOLDER/data
fi
if [ ! -d $SCRIPT_FOLDER/data/animes ]
then
	mkdir $SCRIPT_FOLDER/data/animes
else
	find $SCRIPT_FOLDER/data/animes/* -mmin +2880 -exec rm {} \;			#delete json data if older than 2 days
	find $SCRIPT_FOLDER/data/animes/ongoing.tsv -mmin +720 -exec rm {} \;		#delete ongoing if older than 12h
fi
if [ ! -d $POSTERS_FOLDER ]										#check if exist and create folder for posters
then
	mkdir $POSTERS_FOLDER
else
	find $POSTERS_FOLDER/* -mtime +30 -exec rm {} \;				#delete posters if older than 30 days
fi
if [ ! -d $SCRIPT_FOLDER/ID ]											#check if exist and create folder and file for ID
then
	mkdir $SCRIPT_FOLDER/ID
	touch $SCRIPT_FOLDER/ID/animes.tsv
elif [ ! -f $SCRIPT_FOLDER/ID/animes.tsv ]
then
	touch $SCRIPT_FOLDER/ID/animes.tsv
else
	rm $SCRIPT_FOLDER/ID/animes.tsv
	touch $SCRIPT_FOLDER/ID/animes.tsv
fi
if [ ! -d $SCRIPT_FOLDER/tmp ]										#check if exist and create temp folder cleaned at the start of every run
then
	mkdir $SCRIPT_FOLDER/tmp
else
	rm $SCRIPT_FOLDER/tmp/*
fi
if [ ! -d $LOG_FOLDER ]
then
	mkdir $LOG_FOLDER
fi
if [ ! -d $LOG_FOLDER/animes ]
then
	mkdir $LOG_FOLDER/animes
fi

# Download anime mapping json data
curl "https://raw.githubusercontent.com/Arial-Z/Animes-ID/main/list-animes-id.json" > $SCRIPT_FOLDER/tmp/list-animes-id.json

# Dummy run of PMM and move meta.log for creating tvdb_id and title_plex
if [ "$PMM_INSTALL_TYPE"  == "python_venv" ]
then
	rm $PMM_FOLDER_CONFIG/temp-animes.cache
	$PMM_FOLDER/pmm-venv/bin/python $PMM_FOLDER/plex_meta_manager.py -r --config $PMM_FOLDER_CONFIG/temp-animes.yml
	cp $PMM_FOLDER_CONFIG/logs/meta.log $SCRIPT_FOLDER/tmp
elif [ "$PMM_INSTALL_TYPE"  == "docker" ]
then
	docker exec -i $DOCKER_CONTAINER_NAME chmod 777 config/temp-animes.cache
	docker exec -i $DOCKER_CONTAINER_NAME rm config/temp-animes.cache
	docker exec -i $DOCKER_CONTAINER_NAME python plex_meta_manager.py -r --config config/temp-animes.yml
	docker exec -i $DOCKER_CONTAINER_NAME chmod -R 777 config/logs/meta.log
	cp $PMM_FOLDER_CONFIG/logs/meta.log $SCRIPT_FOLDER/tmp
elif [ "$PMM_INSTALL_TYPE"  == "python" ]
then
	rm $PMM_FOLDER_CONFIG/temp-animes.cache
	python $PMM_FOLDER/plex_meta_manager.py -r --config $PMM_FOLDER_CONFIG/temp-animes.yml
	cp $PMM_FOLDER_CONFIG/logs/meta.log $SCRIPT_FOLDER/tmp
else
	echo "Set Plex Meta Manager install type in conf"
fi

# create clean list-animes.tsv (tvdb_id	title_plex) from meta.log
line_start=$(grep -n "Mapping "$ANIME_LIBRARY_NAME" Library" $SCRIPT_FOLDER/tmp/meta.log | cut -d : -f 1)
line_end=$(grep -n -m1 "$ANIME_LIBRARY_NAME Library Operations" $SCRIPT_FOLDER/tmp/meta.log | cut -d : -f 1)
head -n $line_end $SCRIPT_FOLDER/tmp/meta.log | tail -n $(( $line_end - $line_start - 1 )) | head -n -5 > $SCRIPT_FOLDER/tmp/cleanlog-animes.txt
awk -F"|" '{ OFS = "\t" } ; { gsub(/ /,"",$5) } ; { print substr($5,8),substr($7,2,length($7)-2) }' $SCRIPT_FOLDER/tmp/cleanlog-animes.txt > $SCRIPT_FOLDER/tmp/list-animes-dirty.tsv
sed 's/^[ \t]*//;s/[ \t]*$//' < $SCRIPT_FOLDER/tmp/list-animes-dirty.tsv > $SCRIPT_FOLDER/tmp/list-animes.tsv

# create ID/animes.tsv from the clean list ( tvdb_id	mal_id	title_anime	title_plex )
while IFS=$'\t' read -r tvdb_id mal_id title_anime studio									# First add the override animes to the ID file
do
	if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/ID/animes.tsv | grep -w  $tvdb_id
	then
		if awk -F"\t" '{print $1}' $SCRIPT_FOLDER/tmp/list-animes.tsv | grep -w  $tvdb_id
		then
			line=$(grep -w -n $tvdb_id $SCRIPT_FOLDER/tmp/list-animes.tsv | cut -d : -f 1)
			title_plex=$(sed -n "${line}p" $SCRIPT_FOLDER/tmp/list-animes.tsv | awk -F"\t" '{print $2}')
			printf "$tvdb_id\t$mal_id\t$title_anime\t$title_plex\n" >> $SCRIPT_FOLDER/ID/animes.tsv
			echo "$(date +%Y.%m.%d" - "%H:%M:%S) - override found for : $title_anime / $title_plex" >> $LOG
		fi
	fi
done < $SCRIPT_FOLDER/override-ID-animes.tsv
while IFS=$'\t' read -r tvdb_id title_plex											# then get the other ID from the ID mapping and download json data
do
	if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/ID/animes.tsv | grep -w  $tvdb_id
	then
		mal_id=$(get-mal-id)
		if [[ "$mal_id" == 'null' ]] || [[ "${#mal_id}" == '0' ]]						# Ignore anime with no tvdb to mal id conversion show in the error log you need to add them by hand in override
		then
			echo "$(date +%Y.%m.%d" - "%H:%M:%S) - invalid MAL ID for : tvdb : $tvdb_id / $title_plex" >> $MATCH_LOG
			continue
		fi
		anilist_id=$(get-anilist-id)
		if [[ "$anilist_id" == 'null' ]] || [[ "${#anilist_id}" == '0' ]]				# Ignore anime with no tvdb to mal id conversion show in the error log you need to add them by hand in override
		then
			echo "$(date +%Y.%m.%d" - "%H:%M:%S) - invalid Anilist ID for : tvdb : $tvdb_id / $title_plex" >> $MATCH_LOG
			continue
		fi
		get-mal-infos
		get-anilist-infos
		title_anime=$(get-anilist-title)
		printf "$tvdb_id\t$mal_id\t$title_anime\t$title_plex\n" >> $SCRIPT_FOLDER/ID/animes.tsv
		echo "$(date +%Y.%m.%d" - "%H:%M:%S) - $title_anime / $title_plex added to ID/animes.tsv" >> $LOG
	fi
done < $SCRIPT_FOLDER/tmp/list-animes.tsv

# Create an ongoing list at $SCRIPT_FOLDER/data/animes/ongoing.csv
if [ ! -f $SCRIPT_FOLDER/data/animes/ongoing.tsv ]              												# check if already exist
then
	ongoingpage=1
	while [ $ongoingpage -lt 10 ];																	# get the airing list from jikan API max 9 pages (225 animes)
	do
		curl "https://api.jikan.moe/v4/anime?status=airing&page=$ongoingpage&order_by=member&order=desc&genres_exclude=12&min_score=4" > $SCRIPT_FOLDER/tmp/ongoing-tmp.json
		sleep 2
		jq ".data[].mal_id" -r $SCRIPT_FOLDER/tmp/ongoing-tmp.json >> $SCRIPT_FOLDER/tmp/ongoing.tsv				# store the mal ID of the ongoing show
		if grep "\"has_next_page\":false," $SCRIPT_FOLDER/tmp/ongoing-tmp.json								# stop if page is empty
		then
			break
		fi
		((ongoingpage++))
	done
	while read -r mal_id
	do
		if awk -F"\t" '{print $2}' $SCRIPT_FOLDER/override-ID-animes.tsv | grep -w  $mal_id
		then
			printf "$mal_id\n" >> $SCRIPT_FOLDER/data/animes/ongoing.tsv
		else
			tvdb_id=$(get-tvdb-id)																	# convert the mal id to tvdb id (to get the main anime)
			if [[ "$tvdb_id" == 'null' ]] || [[ "${#tvdb_id}" == '0' ]]										# Ignore anime with no mal to tvdb id conversion
			then
				echo "$(date +%Y.%m.%d" - "%H:%M:%S) - Ongoing invalid TVDB ID for : MAL : $mal_id" >> $LOG
				continue
			else
				if awk -F"\t" '{print $1}' $SCRIPT_FOLDER/override-ID-animes.tsv | grep -w  $tvdb_id
				then
					line=$(grep -w -n $tvdb_id $SCRIPT_FOLDER/override-ID-animes.tsv | cut -d : -f 1)
					mal_id=$(sed -n "${line}p" $SCRIPT_FOLDER/override-ID-animes.tsv | awk -F"\t" '{print $2}')
					printf "$mal_id\n" >> $SCRIPT_FOLDER/data/animes/ongoing.tsv
				else
					mal_id=$(get-mal-id)
					if [[ "$mal_id" == 'null' ]] || [[ "${#mal_id}" == '0' ]]						# Ignore anime with no tvdb to mal id conversion show in the error log you need to add them by hand in override
					then
						echo "$(date +%Y.%m.%d" - "%H:%M:%S) - Ongoing invalid MAL ID for : TVDB : $tvdb_id" >> $LOG
						continue
					else
						printf "$mal_id\n" >> $SCRIPT_FOLDER/data/animes/ongoing.tsv
					fi
				fi
			fi
		fi
	done < $SCRIPT_FOLDER/tmp/ongoing.tsv
fi

# write PMM metadata file from ID/animes.tsv and jikan API
while IFS=$'\t' read -r tvdb_id mal_id title_anime title_plex
do
	get-mal-infos
	echo "  \"$title_anime\":" >> $animes_titles
	echo "    alt_title: \"$title_plex\"" >> $animes_titles
	echo "    sort_title: \"$title_anime\"" >> $animes_titles
	title_eng=$(get-mal-eng-title)
	if [ "$title_eng" == "null" ]
	then
		echo "    original_title: \"$title_anime\"" >> $animes_titles
	else 
		echo "    original_title: \"$title_eng\"" >> $animes_titles
	fi
	printf "$(date +%Y.%m.%d" - "%H:%M:%S) - $title_anime:\n" >> $LOG
	score_mal=$(get-mal-rating)
	echo "    critic_rating: $score_mal" >> $animes_titles									# rating (critic)
	printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\tscore : $score_mal\n" >> $LOG
	mal_tags=$(get-mal-tags)
	echo "    genre.sync: Anime,${mal_tags}"  >> $animes_titles									# tags (genres, themes and demographics from MAL)
	printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\ttags : $mal_tags\n" >> $LOG
	if awk -F"\t" '{print "\""$1"\":"}' $SCRIPT_FOLDER/data/animes/ongoing.tsv | grep -w "$mal_id"		# Ongoing label according to MAL airing list
	then
		echo "    label: Ongoing" >> $animes_titles
		printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\tLabel add Ongoing\n" >> $LOG
	else
		echo "    label.remove: Ongoing" >> $animes_titles
		printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\tLabel remove Ongoing\n" >> $LOG
	fi
	get-mal-studios
	echo "    studio: ${mal_studios}"  >> $animes_titles
	printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\tstudio : $mal_studios\n" >> $LOG
	get-mal-poster																# check / download poster
	echo "    file_poster: $POSTERS_PMM_FOLDER/${mal_id}.jpg" >> $animes_titles
	printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\tPoster added\n" >> $LOG
done < $SCRIPT_FOLDER/ID/animes.tsv