#' Internal function: Get the API response, return a data frame
#'
#' @param apiurl, key, get, region, time
#' @keywords internal
#' @export
getFunction <- function(apiurl, key, get, region, regionin, time, date, period, monthly, category_code, data_type_code, naics, pscode, naics2012, naics2007, naics2002, naics1997, sic) {
	# Return API's built in error message if invalid call
	apiCheck <- function(req) {
		if (req$status_code==400) stop(httr::content(req, as = "text"), call. = FALSE)
		# Some time series don't give error messages, just don't resolve (e.g. SAIPE)
		if (req$status_code==204) stop("204, no content. If using a time series API, check time period inputs - given time period may be unavailable.", call. = FALSE)
		if (identical(httr::content(req, as = "text"), "")) stop("No output to parse", call. = FALSE)
	}

	apiParse <- function (req) {
		if (jsonlite::validate(httr::content(req, as="text"))[1] == FALSE) {
			error_message <- (gsub("<[^>]*>", "", httr::content(req, as="text")))
			stop(paste("API response is not JSON\n Error message:", error_message))
		} else {
			raw <- jsonlite::fromJSON(httr::content(req, as = "text"))
		}
	}

	# Function to clean up column names - particularly ones with periods in them
	cleanColnames <- function(dt) {
		# No trailing punct
		colnames(dt) <- gsub("\\.[[:punct:]]*$", "", colnames(dt))
		# All punctuation becomes underscore
		colnames(dt) <- gsub("[[:punct:]]", "_", colnames(dt))
		# Get rid of repeat underscores
		colnames(dt) <- gsub("(_)\\1+", "\\1", colnames(dt))
		return(dt)
	}

	responseFormat <- function(raw) {
		# Make first row the header
		colnames(raw) <- raw[1, ]
		df <- data.frame(raw)
		df <- df[-1,]
		df <- cleanColnames(df)
		# Make all columns character
		df[] <- lapply(df, as.character)
		# Make columns numeric if they have numbers in the column name - note some APIs use string var names
		# For ACS data, do not make columns numeric if they are ACS annotation variables - ending in MA or EA or SS
		# Do not make label variables (ending in _TTL) for economic APIs numeric
		if(!grepl("acs|ewks|cbp|ase", apiurl)) {
			value_cols <- grep("[0-9]", names(df), value=TRUE)
			for(col in value_cols) df[,col] <- as.numeric(df[,col])
		} else if(grepl("ase/", apiurl)) {
			value_cols <- grep("[0-9]", names(df), value=TRUE)
			error_cols <- grep("MA|EA|SS|_TTL|_NAME|NAICS2012", value_cols, value=TRUE, ignore.case = T)
			for(col in setdiff(value_cols, error_cols)) df[,col] <- as.numeric(df[,col])
		}
		else {
			value_cols <- grep("[0-9]", names(df), value=TRUE)
			error_cols <- grep("MA|EA|SS|_TTL|_NAME", value_cols, value=TRUE, ignore.case = T)
			for(col in setdiff(value_cols, error_cols)) df[,col] <- as.numeric(df[,col])
		}
		row.names(df) <- NULL
		return(df)
	}

	# Assemble call
	req <- httr::GET(apiurl, query = list(key = key, get = get, "for" = region, "in" = regionin, category_code = category_code, data_type_code = data_type_code, time = time, DATE = date, PERIOD = period, MONTHLY = monthly, NAICS=naics, PSCODE=pscode, NAICS2012 = naics2012, NAICS2007 = naics2007, NAICS2002 = naics2002, NAICS1997 = naics1997, SIC = sic))

	# Check the API call for a valid response
	apiCheck(req)

	# If check didn't fail, parse the content
	raw <- apiParse(req)

	# Format the response into a nice data frame
	df <- responseFormat(raw)
}
#' Retrieve Census data from a given API
#'
#' @param name API name - e.g. acs5. See list at https://api.census.gov/data.html
#' @param vintage Year of dataset, e.g. 2014 - not required for timeseries APIs
#' @param key Your Census API key, gotten from https://api.census.gov/data/key_signup.html
#' @param vars List of variables to get
#' @param region Geography to get
#' @param regionin Optional hierarchical geography to limit region
#' @param time,date,period,monthly Optional arguments used for some time series APIs
#' @param category_code,data_type_code Arguments used in Economic Indicators Time Series API
#' @param naics,pscode Arguments used in Annual Survey of Manufactures API
#' @param naics2012,naics2007,naics2002,naics1997,sic Arguments used in Economy Wide Key Statistics APIs and Business Patterns APIs
#' @keywords api
#' @export
#' @examples
#' \donttest{df <- getCensus(name = "acs/acs5", vintage = 2016,
#' 	vars = c("B01001_001E", "NAME", "B01002_001E", "B19013_001E"),
#' 	region = "tract:*", regionin = "state:06")
#' head(df)
#'
#' # Use American Community Survey variable groups to get all data from a given table.
#' # This returns estimates as well as margins of error and annotation flags.
#' acs_group <- getCensus(name = "acs/acs5", vintage = 2016,
#' 	vars = c("NAME", "group(B19013)"),
#' 	region = "county:*")
#' 	head(acs_group)
#'
#' # Retreive block-level data within a specific state and county using a nested regionin argument
#' data2010 <- getCensus(name = "sf1", vintage = 2010,
#'	vars = c("P0010001", "P0030001"),
#'	region = "block:*", regionin = "state:36+county:27")
#' head(data2010)
#'
#' # Retreive block-level data for Decennial Census sf1, 2000
#' # Note, for this dataset a tract needs to be specified to retrieve blocks
#' data2000 <- getCensus(name = "sf1", vintage = 2000,
#' 	vars = c("P001001", "P003001"),
#'	region = "block:*", regionin = "state:36+county:27+tract:010000")
#' head(data2000)
#'
#' # Get time series data
#' saipe <- getCensus(name = "timeseries/poverty/saipe",
#' 	vars = c("NAME", "SAEPOVRT0_17_PT", "SAEPOVRTALL_PT"),
#' 	region = "state:*", time = 2011)
#' head(saipe)
#'
#' # Get county business patterns data for a specific NAICS sector
#'cbp_2016 <- getCensus(name = "cbp",
#'  vintage = "2016",
#'  vars = c("EMP", "ESTAB", "NAICS2012_TTL", "GEO_TTL"),
#'  region = "state:*",
#'  naics2012 = "23")
#'  head(cbp_2016)}
getCensus <- function(name, vintage=NULL, key=Sys.getenv("CENSUS_KEY"), vars, region, regionin=NULL, time=NULL, date=NULL, period=NULL, monthly=NULL, category_code=NULL, data_type_code=NULL, naics=NULL, pscode=NULL, naics2012=NULL, naics2007=NULL, naics2002=NULL, naics1997=NULL, sic=NULL) {
	constructURL <- function(name, vintage) {
		if (is.null(vintage)) {
			apiurl <- paste("https://api.census.gov/data", name, sep="/")
		} else {
			apiurl <- paste("https://api.census.gov/data", vintage, name, sep="/")
		}

		# Handle messy urls
		lastchar <- substr(apiurl, nchar(apiurl), nchar(apiurl))
		if (lastchar=="?" | lastchar=="/") {
			apiurl <- substr(apiurl, 1, nchar(apiurl)-1)
		}
		apiurl
	}

	# Check for key in environment
	key_env <- Sys.getenv("CENSUS_KEY")
	if ((key_env == "" & key == key_env)) {
		stop("'key' argument is missing. A Census API key is required and can be requested at https://api.census.gov/data/key_signup.html.\nPlease add your Census key to your .Renviron - see instructions at https://github.com/hrecht/censusapi#api-key-setup")
	}

	apiurl <- constructURL(name, vintage)

	# Census API max vars per call = 50
	# Splitting function based on work by Nicholas Nagle, https://rpubs.com/nnnagle/19337
	if(length(vars)>50){
		# Split vars into list
		vars <- split(vars, ceiling(seq_along(vars)/50))
		get <- lapply(vars, function(x) paste(x, sep='', collapse=","))
		data <- lapply(get, function(x) getFunction(apiurl, key, x, region, regionin, time, date, period, monthly, category_code, data_type_code, naics, pscode, naics2012, naics2007, naics2002, naics1997, sic))
		colnames <- unlist(lapply(data, names))
		data <- do.call(cbind,data)
		names(data) <- colnames
	} else {
		get <- paste(vars, sep='', collapse=',')
		data <- getFunction(apiurl, key, get, region, regionin, time, date, period, monthly, category_code, data_type_code, naics, pscode, naics2012, naics2007, naics2002, naics1997, sic)
	}
	# If there are any duplicate columns (ie if you put a variable in vars twice) remove the duplicates
	data <- data[, !duplicated(colnames(data))]
	# Reorder columns so that numeric fields follow non-numeric fields
	# data <- data[,c(which(sapply(data, class)!='numeric'), which(sapply(data, class)=='numeric'))]
	# Reorder columns so that lowercase column names (geographies) are first
	data <- data[,c(which(grepl("[a-z]", colnames(data))), which(!grepl("[a-z]", colnames(data))))]
	return(data)
}
