#' Pneumonia and Influenza Mortality Surveillance
#'
#' The National Center for Health Statistics (NCHS) collects and disseminates the Nation's
#' official vital statistics. NCHS collects death certificate data from state vital
#' statistics offices for virtually all deaths occurring in the United States. Pneumonia
#' and influenza (P&I) deaths are identified based on ICD-10
#' multiple cause of death codes.\cr
#' \cr
#' NCHS Mortality Surveillance System data are presented by the week the death occurred
#' at the national, state, and HHS Region levels. Data on the percentage of deaths due
#' to P&I on a national level are released two weeks after the week of death to allow
#' for collection of enough data to produce a stable percentage.  States and HHS regions
#' with less than 20% of the expected total deaths (average number of total deaths
#' reported by week during 2008-2012) will be marked as insufficient data. Collection
#' of complete data is not expected at the time of initial report, and a reliable
#' percentage of deaths due to P&I is not anticipated at the U.S. Department of Health
#' and Human Services region or state level within this two week period.  The data for
#' earlier weeks are continually revised and the proportion of deaths due to P&I may
#' increase or decrease as new and updated death certificate data are received by NCHS.\cr
#' \cr
#' The seasonal baseline of P&I deaths is calculated using a periodic regression model
#' that incorporates a robust regression procedure applied to data from the previous
#' five years. An increase of 1.645 standard deviations above the seasonal baseline
#' of P&I deaths is considered the "epidemic threshold," i.e., the point at which
#' the observed proportion of deaths attributed to pneumonia or influenza was
#' significantly higher than would be expected at that time of the year in the
#' absence of substantial influenza-related mortality. Baselines and thresholds are
#' calculated at the national and regional level and by age group.
#'
#' @md
#' @param coverage_area coverage area for data (national, state or region)
#' @note Queries for "state" and "region" are not "instantaneous" and can near or over 30s retrieval delays.
#' @references
#' - [Pneumonia and Influenza Mortality Surveillance Portal](https://gis.cdc.gov/grasp/fluview/mortality.html)
#' @export
#' @examples \dontrun{
#' ndf <- pi_mortality()
#' sdf <- pi_mortality("state")
#' rdf <- pi_mortality("region")
#' }
pi_mortality <- function(coverage_area=c("national", "state", "region")) {

  coverage_area <- match.arg(tolower(coverage_area), choices = c("national", "state", "region"))

  us_states <- read.csv("https://gis.cdc.gov/grasp/fluview/Flu7References/Data/USStates.csv",
                        stringsAsFactors=FALSE)
  us_states <- setNames(us_states, c("region_name", "subgeoid", "state_abbr"))
  us_states <- us_states[,c("region_name", "subgeoid")]
  us_states$subgeoid <- as.character(us_states$subgeoid)

  meta <- jsonlite::fromJSON("https://gis.cdc.gov/grasp/flu7/GetPhase07InitApp?appVersion=Public")

  mapcode_df <- setNames(meta$nchs_mapcode[,c("mapcode", "description")], c("map_code", "callout"))
  mapcode_df$map_code <- as.character(mapcode_df$map_code)

  geo_df <- meta$nchs_geo_dim
  geo_df$geoid <- as.character(geo_df$geoid)

  age_df <- setNames(meta$nchs_ages, c("ageid", "age_label"))
  age_df$ageid <- as.character(age_df$ageid)

  mwmr_df <- meta$mmwr
  mwmr_df$mmwrid <- as.character(mwmr_df$mmwrid)
  mwmr_df <- setNames(mwmr_df,
                      c("mmwrid", "weekend", "mwmr_weeknumber", "weekstart",
                        "year", "yearweek", "mwmr_seasonid", "mwmr_label", "weekendlabel"))

  sum_df <- meta$nchs_summary
  sum_df$seasonid <- as.character(sum_df$seasonid)
  sum_df$ageid <- as.character(sum_df$ageid)
  sum_df$geoid <- as.character(sum_df$geoid)

  httr::POST(
    url = "https://gis.cdc.gov/grasp/flu7/PostPhase07DownloadData",
    httr::user_agent(.cdcfluview_ua),
    httr::add_headers(
      Origin = "https://gis.cdc.gov",
      Accept = "application/json, text/plain, */*",
      Referer = "https://gis.cdc.gov/grasp/fluview/mortality.html"
    ),
    encode = "json",
    body = list(
      AppVersion = "Public",
      AreaParameters = list(list(ID=.geoid_map[coverage_area])),
      SeasonsParameters = lapply(meta$seasons$seasonid, function(.x) { list(ID=as.integer(.x)) }),
      AgegroupsParameters = list(list(ID="1"))
    ),
    # httr::verbose(),
    httr::timeout(60)
  ) -> res

  httr::stop_for_status(res)

  res <- httr::content(res, as="parsed", flatten=TRUE)

  dplyr::bind_rows(res$seasons) %>%
    dplyr::left_join(mapcode_df, "map_code") %>%
    dplyr::left_join(geo_df, "geoid") %>%
    dplyr::left_join(age_df, "ageid") %>%
    dplyr::left_join(mwmr_df, "mmwrid") -> xdf

  xdf <- dplyr::mutate(xdf, coverage_area = coverage_area)

  if (coverage_area == "state") {
    xdf <- dplyr::left_join(xdf, us_states, "subgeoid")
  } else if (coverage_area == "region") {
    xdf$region_name <- sprintf("Region %s", xdf$subgeoid)
  } else {
    xdf$region_name <- NA_character_
  }

  xdf[,c("seasonid", "baseline", "threshold", "percent_pni",
         "percent_complete", "number_influenza", "number_pneumonia",
         "all_deaths", "Total_PnI", "weeknumber", "geo_description",
         "age_label", "weekend", "weekstart", "year", "yearweek",
         "coverage_area", "region_name", "callout")] -> xdf

  suppressWarnings(xdf$baseline <- to_num(xdf$baseline))
  suppressWarnings(xdf$threshold <- to_num(xdf$threshold))
  suppressWarnings(xdf$percent_pni <- to_num(xdf$percent_pni) / 100)
  suppressWarnings(xdf$percent_complete <- to_num(xdf$percent_complete) / 100)
  suppressWarnings(xdf$number_influenza <- to_num(xdf$number_influenza))
  suppressWarnings(xdf$number_pneumonia <- to_num(xdf$number_pneumonia))
  suppressWarnings(xdf$all_deaths <- to_num(xdf$all_deaths))
  suppressWarnings(xdf$Total_PnI <- to_num(xdf$Total_PnI))
  suppressWarnings(xdf$weekend <- as.Date(xdf$weekend))
  suppressWarnings(xdf$weekstart <- as.Date(xdf$weekstart))

  xdf <- .mcga(xdf)

  xdf

}


