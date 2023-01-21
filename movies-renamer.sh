#!/bin/bash

SCRIPT_FOLDER=$(dirname $(readlink -f $0))
source $SCRIPT_FOLDER/config.conf
LOG=$LOG_FOLDER/movies/$(date +%Y.%m.%d).log
MATCH_LOG=$LOG_FOLDER/missing-id.log

# function
function get-mal-id () {
imdb_jq=$(echo $imdb_id | awk '{print "\""$1"\""}' )
jq ".[] | select( .imdb_id == ${imdb_jq} )" -r $SCRIPT_FOLDER/tmp/list-animes-id.json | jq .mal_id | sort -n | head -1
}
function get-anilist-id () {
imdb_jq=$(echo $imdb_id | awk '{print "\""$1"\""}' )
jq ".[] | select( .imdb_id == ${imdb_jq} )" -r $SCRIPT_FOLDER/tmp/list-animes-id.json | jq .anilist_id | sort -n | head -1
}
function get-mal-infos () {
if [ ! -f $SCRIPT_FOLDER/data/movies/$mal_id.json ]
then
	sleep 0.5
	curl "https://api.jikan.moe/v4/anime/$mal_id" > $SCRIPT_FOLDER/data/movies/$mal_id.json
	sleep 1.5
fi
}
function get-anilist-infos () {
if [ ! -f $SCRIPT_FOLDER/data/movies/title-$mal_id.json ]
then
	sleep 0.5
	curl 'https://graphql.anilist.co/' \
	-X POST \
	-H 'content-type: application/json' \
	--data '{ "query": "{ Media(id: '"$anilist_id"') { title { romaji } } }" }' > $SCRIPT_FOLDER/data/movies/title-$mal_id.json
	sleep 1.5
fi
}
function get-anilist-title () {
jq .data.Media.title.romaji -r $SCRIPT_FOLDER/data/movies/title-$mal_id.json
}
function get-mal-eng-title () {
jq .data.title_english -r $SCRIPT_FOLDER/data/movies/$mal_id.json
}
function get-mal-rating () {
jq .data.score -r $SCRIPT_FOLDER/data/movies/$mal_id.json
}
function get-mal-poster () {
if [ ! -f $POSTERS_FOLDER/$mal_id.jpg ]
then
	sleep 0.5
	mal_poster_url=$(jq .data.images.jpg.large_image_url -r $SCRIPT_FOLDER/data/movies/$mal_id.json)
	curl "$mal_poster_url" > $POSTERS_FOLDER/$mal_id.jpg
	sleep 1.5
else
	postersize=$(du -b $POSTERS_FOLDER/$mal_id.jpg | awk '{ print $1 }')
	if [[ $postersize -lt 10000 ]]
	then
		rm $POSTERS_FOLDER/$mal_id.jpg
		sleep 0.5
		mal_poster_url=$(jq .data.images.jpg.large_image_url -r $SCRIPT_FOLDER/data/movies/$mal_id.json)
		curl "$mal_poster_url" > $POSTERS_FOLDER/$mal_id.jpg
		sleep 1.5
	fi
fi
}
function get-mal-tags () {
(jq '.data.genres  | .[] | .name' -r $SCRIPT_FOLDER/data/movies/$mal_id.json && jq '.data.demographics  | .[] | .name' -r $SCRIPT_FOLDER/data/movies/$mal_id.json) | awk '{print $0}' | paste -s -d, -
}
function get-mal-studios() {
if awk -F"\t" '{print $2}' $SCRIPT_FOLDER/override-ID-movies.tsv | grep -w  $mal_id
then
     line=$(grep -w -n $mal_id $SCRIPT_FOLDER/override-ID-movies.tsv | cut -d : -f 1)
     studio=$(sed -n "${line}p" $SCRIPT_FOLDER/override-ID-movies.tsv | awk -F"\t" '{print $4}')
     if [[ -z "$studio" ]]
     then
          mal_studios=$(jq '.data.studios[0] | [.name]| @tsv' -r $SCRIPT_FOLDER/data/movies/$mal_id.json)
     else
          mal_studios=$(echo "$studio")
     fi
else
	mal_studios=$(jq '.data.studios[0] | [.name]| @tsv' -r $SCRIPT_FOLDER/data/movies/$mal_id.json)
fi
}

# download pmm animes mapping and check if files and folder exist
if [ ! -f $movies_titles ]
then
	echo "metadata:" > $movies_titles
else
	rm $movies_titles
	echo "metadata:" > $movies_titles
fi
if [ ! -d $SCRIPT_FOLDER/data ]											#check if exist and create folder for json data
then
	mkdir $SCRIPT_FOLDER/data
fi
if [ ! -d $SCRIPT_FOLDER/data/movies ]
then
	mkdir $SCRIPT_FOLDER/data/movies
else
	find $SCRIPT_FOLDER/data/movies/* -mmin +2880 -exec rm {} \;				#delete json data if older than 2 days
fi
if [ ! -d $POSTERS_FOLDER ]
then
	mkdir $POSTERS_FOLDER
else
	find $POSTERS_FOLDER/* -mtime +30 -exec rm {} \;
fi
if [ ! -d $SCRIPT_FOLDER/ID ]
then
	mkdir $SCRIPT_FOLDER/ID
	touch $SCRIPT_FOLDER/ID/movies.tsv
elif [ ! -f $SCRIPT_FOLDER/ID/movies.tsv ]
then
	touch $SCRIPT_FOLDER/ID/movies.tsv
else
	rm $SCRIPT_FOLDER/ID/movies.tsv
	touch $SCRIPT_FOLDER/ID/movies.tsv
fi
if [ ! -d $SCRIPT_FOLDER/tmp ]
then
	mkdir $SCRIPT_FOLDER/tmp
else
	rm $SCRIPT_FOLDER/tmp/*
fi
if [ ! -d $LOG_FOLDER ]
then
	mkdir $LOG_FOLDER
fi
if [ ! -d $LOG_FOLDER/movies ]
then
	mkdir $LOG_FOLDER/movies
fi

# Download anime mapping json data
curl "https://raw.githubusercontent.com/Arial-Z/Animes-ID/main/list-animes-id.json" > $SCRIPT_FOLDER/tmp/list-animes-id.json

# Dummy run of PMM and move meta.log for creating imdb_id and title_plex
if [ "$PMM_INSTALL_TYPE"  == "python_venv" ]
then
	rm $PMM_FOLDER_CONFIG/temp-movies.cache
	$PMM_FOLDER/pmm-venv/bin/python $PMM_FOLDER/plex_meta_manager.py -r --config $PMM_FOLDER_CONFIG/temp-movies.yml
	cp $PMM_FOLDER_CONFIG/logs/meta.log $SCRIPT_FOLDER/tmp
elif [ "$PMM_INSTALL_TYPE"  == "docker" ]
then
	docker exec -i $DOCKER_CONTAINER_NAME chmod 777 config/temp-movies.cache
	docker exec -i $DOCKER_CONTAINER_NAME rm config/temp-movies.cache
	docker exec -i $DOCKER_CONTAINER_NAME python plex_meta_manager.py -r --config config/temp-movies.yml
	docker exec -i $DOCKER_CONTAINER_NAME chmod -R 777 config/logs/meta.log
	cp $PMM_FOLDER_CONFIG/logs/meta.log $SCRIPT_FOLDER/tmp
elif [ "$PMM_INSTALL_TYPE"  == "python" ]
then
	rm $PMM_FOLDER_CONFIG/temp-movies.cache
	python $PMM_FOLDER/plex_meta_manager.py -r --config $PMM_FOLDER_CONFIG/temp-movies.yml
	cp $PMM_FOLDER_CONFIG/logs/meta.log $SCRIPT_FOLDER/tmp
else
	echo "Set Plex Meta Manager install type in conf"
fi

# create clean list-movies.tsv (imdb_id | title_plex) from meta.log
line_start=$(grep -n "Mapping $MOVIE_LIBRARY_NAME Library" $SCRIPT_FOLDER/tmp/meta.log | cut -d : -f 1)
line_end=$(grep -n -m1 "$MOVIE_LIBRARY_NAME Library Operations" $SCRIPT_FOLDER/tmp/meta.log | cut -d : -f 1)
head -n $line_end $SCRIPT_FOLDER/tmp/meta.log | tail -n $(( $line_end - $line_start - 1 )) | head -n -5 > $SCRIPT_FOLDER/tmp/cleanlog-movies.txt
awk -F"|" '{ OFS = "\t" } ; { gsub(/ /,"",$6) } ; { print  substr($6,8),substr($7,2,length($7)-2) }' $SCRIPT_FOLDER/tmp/cleanlog-movies.txt > $SCRIPT_FOLDER/tmp/list-movies.tsv

# create ID/movies.tsv ( imdb_id | mal_id | title_anime | title_plex )
while IFS=$'\t' read -r imdb_id mal_id title_anime studio									# First add the override animes to the ID file
do
	if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/ID/movies.tsv | grep -w  $imdb_id
	then
		if awk -F"\t" '{print $1}' $SCRIPT_FOLDER/tmp/list-movies.tsv | grep -w  $imdb_id
		then
			line=$(grep -w -n $imdb_id $SCRIPT_FOLDER/tmp/list-movies.tsv | cut -d : -f 1)
			title_plex=$(sed -n "${line}p" $SCRIPT_FOLDER/tmp/list-movies.tsv | awk -F"\t" '{print $2}')
			printf "$imdb_id\t$mal_id\t$title_anime\t$title_plex\n" >> $SCRIPT_FOLDER/ID/movies.tsv
			echo "$(date +%Y.%m.%d" - "%H:%M:%S) - override found for : $title_anime / $title_plex" >> $LOG
		fi
	fi
done < $SCRIPT_FOLDER/override-ID-movies.tsv
while IFS=$'\t' read -r imdb_id title_plex											# then get the other ID from the ID mapping and download json data
do
	if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/ID/movies.tsv | grep -w  $imdb_id
	then
		mal_id=$(get-mal-id)
		if [[ "$mal_id" == 'null' ]] || [[ "${#mal_id}" == '0' ]]						# Ignore anime with no tvdb to mal id conversion show in the error log you need to add them by hand in override
		then
			echo "$(date +%Y.%m.%d" - "%H:%M:%S) - invalid MAL ID for : imdb : $imdb_id / $title_plex" >> $MATCH_LOG
			continue
		fi
		anilist_id=$(get-anilist-id)
		if [[ "$anilist_id" == 'null' ]] || [[ "${#anilist_id}" == '0' ]]				# Ignore anime with no tvdb to mal id conversion show in the error log you need to add them by hand in override
		then
			echo "$(date +%Y.%m.%d" - "%H:%M:%S) - invalid Anilist ID for : imdb : $imdb_id / $title_plex" >> $MATCH_LOG
			continue
		fi
		get-mal-infos
		get-anilist-infos
		title_anime=$(get-anilist-title)
		printf "$imdb_id\t$mal_id\t$title_anime\t$title_plex\n" >> $SCRIPT_FOLDER/ID/movies.tsv
		echo "$(date +%Y.%m.%d" - "%H:%M:%S) - $title_anime / $title_plex added to ID/movies.tsv" >> $LOG
	fi
done < $SCRIPT_FOLDER/tmp/list-movies.tsv

# write PMM metadata file from ID/movies.tsv and jikan API
while IFS=$'\t' read -r imdb_id mal_id title_anime title_plex
do
	get-mal-infos
	echo "  \"$title_anime\":" >> $movies_titles
	echo "    alt_title: \"$title_plex\"" >> $movies_titles
	echo "    sort_title: \"$title_anime\"" >> $movies_titles
	title_eng=$(get-mal-eng-title)
	if [ "$title_eng" == "null" ]
	then
		echo "    original_title: \"$title_anime\"" >> $movies_titles
	else 
		echo "    original_title: \"$title_eng\"" >> $movies_titles
	fi
	printf "$(date +%Y.%m.%d" - "%H:%M:%S) - $title_anime:\n" >> $LOG
	score_mal=$(get-mal-rating)
	echo "    critic_rating: $score_mal" >> $movies_titles									# rating (critic)
	printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\tscore : $score_mal\n" >> $LOG
	mal_tags=$(get-mal-tags)
	echo "    genre.sync: Anime,${mal_tags}"  >> $movies_titles									# tags (genres, themes and demographics from MAL)
	printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\ttags : $mal_tags\n" >> $LOG
	get-mal-studios
	echo "    studio: ${mal_studios}"  >> $movies_titles
	printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\tstudio : $mal_studios\n" >> $LOG
	get-mal-poster																		# check / download poster
	if [ "$PMM_INSTALL_TYPE"  == "docker" ]
	then
		echo "    file_poster: $POSTERS_PMM_FOLDER/${mal_id}.jpg" >> $movies_titles
		printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\tPoster added\n" >> $LOG
	else
		echo "    file_poster: $POSTERS_FOLDER/${mal_id}.jpg" >> $movies_titles
		printf "$(date +%Y.%m.%d" - "%H:%M:%S)\t\tPoster added\n" >> $LOG
	fi
done < $SCRIPT_FOLDER/ID/movies.tsv