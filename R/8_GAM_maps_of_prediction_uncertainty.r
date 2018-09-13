################################################################################
# Author: Petr Keil
# Email: pkeil@seznam.cz
# Date: April 26 2018
################################################################################

# Description: Here is where model SMOOTH is used to generate predictions to the
# regular global network of 1 ha plots, and to the grid of large hexagons.


################################################################################

# clean the workspace and load the libraries
source("0_libraries_functions_settings.r")


################################################################################
### Read, transform and scale the data

# read the data
pts <- read.csv(file="../Data/GRIDS/Fine_points_with_environment.csv")
grid5 <- readOGR(dsn = "../Data/GRIDS", layer = "hex5_with_environment")
grid5 <- spTransform(x = grid5, CRSobj = WGS84)

# -----------------------------------------

pts$Tree_dens <- (pts$TREE_DENS + 1) / pts$A # calculate tree density (note the x+1 step!!)
pts <- data.frame(pts, Area_km = 0.01, min_DBH = 0, DAT_TYPE = "Plot")

# tree density at the grid level
grid5$Tree_dens <- (grid5$TREE_DENS + 1) / grid5$LandArea
grid5@data <- data.frame(grid5@data, min_DBH = 0, DAT_TYPE = "Country")

# -----------------------------------------

pts <- dplyr::select(pts, Area_km, Tree_dens, min_DBH, 
                     GPP, ANN_T, ISO_T, MIN_P, P_SEAS, ALT_DIF,
                     ISLAND, Lat, Lon, DAT_TYPE) %>%
              mutate(Area_km = log(Area_km), Tree_dens=log(Tree_dens))

grid5.dat <- dplyr::select(grid5@data, Area_km = LandArea, Tree_dens, min_DBH,
                           GPP, ANN_T, ISO_T, MIN_P, P_SEAS, ALT_DIF,
                           ISLAND, Lat, Lon, DAT_TYPE) %>%
                    mutate(Area_km = log(Area_km), Tree_dens=log(Tree_dens))

# get the scaling constants that were used to scale the raw plot and country data:
scal.tab <- read.csv("scale_tab.csv")
scal.tab <- scal.tab[scal.tab$var %in% c("ET","WARM_T") == FALSE,]

# scale the grid data in the same way as the original data
pts[,1:9] <- scale(pts[,1:9],
                   center = scal.tab$centr, 
                   scale = scal.tab$scale)

grid5.dat[,1:9] <- scale(grid5.dat[,1:9],
                   center = scal.tab$centr, 
                   scale = scal.tab$scale)

################################################################################
### Make the predictions

# load the saved SMOOTH model that will be used for the global predictions
library(mgcv)
load("../STAN_models/gam_SMOOTH.Rdata")
load("../STAN_models/brms_SMOOTH.RData")

################################################################################
### Predictions in hexagons

# predict S from the model SMOOTH
grid.pred.S.brm <- data.frame(predict(brm.SMOOTH, 
                              newdata = grid5.dat,
                              probs = c(0.025, 0.25, 0.5, 0.75, 0.975)))

names(grid.pred.S.brm)[1] <- "S"
grid.pred.S.brm <- data.frame(grid.pred.S.brm, 
                              ratio.95 = grid.pred.S.brm$X97.5.ile / grid.pred.S.brm$X2.5.ile)
  
plot(log10(ratio.95)~S, data = grid.pred.S.brm)


# merge with the original grid
grid5@data <- data.frame(grid5@data, grid.pred.S.brm)
grid5@data$id <- as.character(grid5@data$id)

# remove cells with little land area
good.cells <-  grid5@data$LandArea / grid5@data$CellArea > 0.5
good.cells[is.na(good.cells)] <- FALSE
grid5 <- grid5[good.cells,]

# remove cells with 0 or NA species predicted
good.cells <- grid5@data$S > 1
good.cells[is.na(good.cells)] <- FALSE
grid5 <- grid5[good.cells, ]


################################################################################
### Predictions in 1 ha plots

# predict S in the plots from the SMOOTH model
plot.pred.S.brm <- predict(brm.SMOOTH, 
                           newdata = pts, 
                           type="response",
                           probs = c(0.025, 0.25, 0.5, 0.75, 0.975))
plot.pred.S.brm <- as.data.frame(plot.pred.S.brm)

names(plot.pred.S.brm)[1] <- "S"
plot.pred.S.brm <- data.frame(plot.pred.S.brm, 
                              ratio.95 = plot.pred.S.brm$`97.5%ile` / plot.pred.S.brm$`2.5%ile`)



# put all together
plot.preds <- data.frame(pts, 
                         plot.pred.S.brm)

# remove predictions of S < 0.8 (an arbitrarily selected threshold)
plot.preds$S[plot.preds$S < 0.8] <- NA

plot.preds <- plot.preds[rowSums(is.na(plot.preds)) == 0,]

# put predictions to a spatial object
plot.preds <- SpatialPointsDataFrame(coords = data.frame(plot.preds$Lon, plot.preds$Lat), 
                                     data = plot.preds, 
                                     proj4string = CRS(WGS84))






# ------------------------------------------------------------------------------
# transform the data for fancy plotting
plot.preds.ml <- spTransform(plot.preds, CRSobj = MOLLWEIDE)
plot.preds.ml <- data.frame(plot.preds.ml@data, 
                            data.frame(X=coordinates(plot.preds.ml)[,1],
                                       Y=coordinates(plot.preds.ml)[,2]))

grid5.ml <- spTransform(grid5, CRSobj=MOLLWEIDE)
grid5.mlf <- tidy(grid5.ml, region="id")
grid5.mlf <- left_join(x=grid5.mlf, y=grid5.ml@data, by="id")



################################################################################
# PLOTTING THE MAPS 

# Read the shapefiles 

  # coutnry boundaries
  CNTR <- readOGR(dsn="../Data/COUNTRIES", layer="COUNTRIES")
  CNTRml <- spTransform(CNTR, CRSobj=MOLLWEIDE)
  CNTRml <- tidy(CNTRml, region="NAME")
  
  # global mainlands (not divided by country boundaries)
  MAINL <- readOGR(dsn = "../Data/COUNTRIES", layer = "GSHHS_i_L1_simple")
  MAINL <- spTransform(MAINL, CRSobj = CRS(MOLLWEIDE))
  MAINL <- tidy(MAINL, region="id")
  
  # equator, tropics, and polar circles
  LINES <- readOGR(dsn = "../Data/COUNTRIES", layer = "ne_110m_geographic_lines")
  LINES <- spTransform(LINES, CRSobj = CRS(MOLLWEIDE))
  LINES <- tidy(LINES, region="name")


# Set the minimalist theme for the plotting
blank.theme <- theme(axis.line=element_blank(),axis.text.x=element_blank(),
                     axis.text.y=element_blank(),axis.ticks=element_blank(),
                     axis.title.x=element_blank(),
                     axis.title.y=element_blank(),
                     legend.position=c(0.63, 0.09),
                     legend.direction = "horizontal",
                     legend.title = element_blank(),
                     legend.title.align = 0,
                     #plot.title = element_text(hjust = 0),
                     plot.subtitle = element_text(vjust=-3),
                     panel.background=element_blank(),
                     panel.border=element_blank(),panel.grid.major=element_blank(),
                     panel.grid.minor=element_blank(),plot.background=element_blank(),
                     plot.title = element_text(face=quote(bold)))

# ------------------------------------------------------------------------------

plot.gr.high <- ggplot(grid5.mlf, aes(long, lat, group=group)) +
  geom_polygon(data=LINES,  aes(long, lat, group=group), 
               colour="darkgrey", size=0.2) +
  geom_polygon(data=MAINL, aes(long, lat, group=group), 
               fill="white", colour=NA, size=.2) +
  geom_polygon(aes(fill=X97.5.ile)) + 
  geom_polygon(data=MAINL, aes(long, lat, group=group), 
               fill=NA, colour="black", size=.2) +
  scale_fill_distiller(palette = "Spectral", 
                       name=expression(S[hex]), 
                       limits=c(1,max(grid5.mlf$X97.5.ile)),
                       trans="log10") +
  scale_x_continuous(limits = c(-12000000, 16000000)) +
  scale_y_continuous(limits = c(-6.4e+06, 8.8e+06)) +
  xlab("") + ylab("") +
  labs(subtitle = "97.5% quantile", title="a") +
  theme_minimal() + blank.theme + theme(plot.title = element_text(face=quote(bold)))
#plot.gr.high

# predicted S in hexagons
plot.gr.S <- ggplot(grid5.mlf, aes(long, lat, group=group)) +
  geom_polygon(data=LINES,  aes(long, lat, group=group), 
               colour="darkgrey", size=0.2) +
  geom_polygon(data=MAINL, aes(long, lat, group=group), 
               fill="white", colour=NA, size=.2) +
  geom_polygon(aes(fill=X50.ile)) + 
  geom_polygon(data=MAINL, aes(long, lat, group=group), 
               fill=NA, colour="black", size=.2) +
  scale_fill_distiller(palette = "Spectral", 
                       name=expression(S[hex]), 
                       limits=c(1,max(grid5.mlf$X97.5.ile)),
                       trans="log10") +
  scale_x_continuous(limits = c(-12000000, 16000000)) +
  scale_y_continuous(limits = c(-6.4e+06, 8.8e+06)) +
  xlab("") + ylab("") +
  labs(subtitle = "50% quantile", title="c") +
  theme_minimal() + blank.theme + theme(plot.title = element_text(face=quote(bold)))
#plot.gr.S

plot.gr.low <- ggplot(grid5.mlf, aes(long, lat, group=group)) +
  geom_polygon(data=LINES,  aes(long, lat, group=group), 
               colour="darkgrey", size=0.2) +
  geom_polygon(data=MAINL, aes(long, lat, group=group), 
               fill="white", colour=NA, size=.2) +
  geom_polygon(aes(fill=X2.5.ile)) + 
  geom_polygon(data=MAINL, aes(long, lat, group=group), 
               fill=NA, colour="black", size=.2) +
  scale_fill_distiller(palette = "Spectral", 
                       name=expression(S[hex]), 
                       limits=c(1,max(grid5.mlf$X97.5.ile)),
                       trans="log10") +
  scale_x_continuous(limits = c(-12000000, 16000000)) +
  scale_y_continuous(limits = c(-6.4e+06, 8.8e+06)) +
  xlab("") + ylab("") +
  labs(subtitle = "2.5% quantile", title="e") +
  theme_minimal() + blank.theme + theme(plot.title = element_text(face=quote(bold)))
#plot.gr.low



# ------------------------------------------------------------------------------

plot.pl.high <- ggplot(MAINL, aes(long, lat, group=group)) +
  geom_polygon(data=LINES,  aes(long, lat, group=group), 
               colour="darkgrey", size=0.2) +
  geom_polygon(colour=NA, fill="white", size=.2) + 
  geom_point(data=plot.preds.ml, size=0.01,
             aes(x=X, y=Y, group=NULL, colour=X97.5.ile))  +
  geom_polygon(colour="black", fill=NA, size=.2) + 
  scale_colour_distiller(palette = "Spectral", 
                         name=expression(S[plot]),
                         limits=c(1,max(plot.preds.ml$X97.5.ile)),
                         trans="log10") +
  scale_x_continuous(limits = c(-12000000, 16000000)) +
  scale_y_continuous(limits = c(-6.4e+06, 8.8e+06)) +
  xlab("") + ylab("") +
  labs(subtitle = "97.5% quantile", title="b") +
  theme_minimal() + blank.theme + theme(plot.title = element_text(face=quote(bold)))

#plot.pl.high

plot.pl.S <- ggplot(MAINL, aes(long, lat, group=group)) +
  geom_polygon(data=LINES,  aes(long, lat, group=group), 
               colour="darkgrey", size=0.2) +
  geom_polygon(colour=NA, fill="white", size=.2) + 
  geom_point(data=plot.preds.ml, size=0.01,
             aes(x=X, y=Y, group=NULL, colour=X50.ile))  +
  geom_polygon(colour="black", fill=NA, size=.2) + 
  scale_colour_distiller(palette = "Spectral", 
                         name=expression(S[plot]),
                         limits=c(1,max(plot.preds.ml$X97.5.ile)),
                         trans="log10") +
  scale_x_continuous(limits = c(-12000000, 16000000)) +
  scale_y_continuous(limits = c(-6.4e+06, 8.8e+06)) +
  xlab("") + ylab("") +
  labs(subtitle = "50% quantile", title="d") +
  theme_minimal() + blank.theme + theme(plot.title = element_text(face=quote(bold)))

#plot.pl.S 

plot.pl.low <- ggplot(MAINL, aes(long, lat, group=group)) +
  geom_polygon(data=LINES,  aes(long, lat, group=group), 
               colour="darkgrey", size=0.2) +
  geom_polygon(colour=NA, fill="white", size=.2) + 
  geom_point(data=plot.preds.ml, size=0.01,
             aes(x=X, y=Y, group=NULL, colour=X2.5.ile))  +
  geom_polygon(colour="black", fill=NA, size=.2) + 
  scale_colour_distiller(palette = "Spectral", 
                         name=expression(S[plot]),
                         limits=c(1,max(plot.preds.ml$X97.5.ile)),
                         trans="log10") +
  scale_x_continuous(limits = c(-12000000, 16000000)) +
  scale_y_continuous(limits = c(-6.4e+06, 8.8e+06)) +
  xlab("") + ylab("") +
  labs(subtitle = "2.5% quantile", title="f") +
  theme_minimal() + blank.theme + theme(plot.title = element_text(face=quote(bold)))

#plot.pl.low


# ------------------------------------------------------------------------------
# more uncertainty plots
grid.rank <- grid5@data[order(grid5$X50.ile), ]

rank.gr.lin <- ggplot(data = grid.rank, aes(x = order(X50.ile), y = X50.ile)) + 
  geom_linerange(aes(x = order(S), ymin = X2.5.ile, ymax = X97.5.ile), 
                 #size = 1, 
                 colour="lightgrey") +
  geom_linerange(aes(x = order(S), ymin = X25.ile, ymax = X75.ile), 
                 #size = 1, 
                 colour="darkgrey") +
  geom_point(size = 0.5) + theme_bw() +
  xlab("Rank") + ylab("Predicted S")  + ggtitle("g") + 
  theme(plot.title = element_text(face=quote(bold)))
# rank.gr.lin


rank.gr.log <- ggplot(data = grid.rank, aes(x = order(X50.ile), y = X50.ile)) + 
               geom_linerange(aes(x = order(S), ymin = X2.5.ile, ymax = X97.5.ile), 
                              #size = 1, 
                              colour="lightgrey") +
               geom_linerange(aes(x = order(S), ymin = X25.ile, ymax = X75.ile), 
                              #size = 1, 
                              colour="darkgrey") +
               scale_y_continuous(trans = "log10", 
                                   # limits=c(0.1, max(grid5$X97.5.ile)),
                                  labels = c(1,10,100,1000, 10000),
                                  breaks = c(1,10,100,1000, 10000)) +
               xlab("Rank") + ylab("Predicted S") + ggtitle("h") +
               geom_point(size = 0.5) + theme_bw() + 
               theme(plot.title = element_text(face=quote(bold)))
rank.gr.log

               
plot.rank <- plot.preds.ml[order(plot.preds.ml$X50.ile), ]


rank.pl.lin <- ggplot(data = plot.rank, aes(x = order(X50.ile), y = X50.ile)) + 
  geom_linerange(aes(x = order(S), ymin = X2.5.ile, ymax = X97.5.ile), 
                 #size = 1, 
                 colour="lightgrey") +
  geom_linerange(aes(x = order(S), ymin = X25.ile, ymax = X75.ile), 
                 #size = 1, 
                 colour="darkgrey") +
  geom_point(size = 0.5) + theme_bw() +
  xlab("Rank") + ylab("Predicted S") + ggtitle("i") + 
  theme(plot.title = element_text(face=quote(bold)))
#rank.pl.lin

rank.pl.log <- ggplot(data = plot.rank, aes(x = order(X50.ile), y = X50.ile)) + 
               geom_linerange(aes(x = order(S), ymin = X2.5.ile, ymax = X97.5.ile), 
                              #size = 1,
                              colour="lightgrey") +
               geom_linerange(aes(x = order(S), ymin = X25.ile, ymax = X75.ile), 
                              #size = 1, 
                              colour="darkgrey") +
               scale_y_continuous(trans = "log10", 
                                  # limits=c(0.1, max(grid5$X97.5.ile)),
                                  labels = c(1,10,100,1000, 10000),
                                  breaks = c(1,10,100,1000, 10000)) +
               xlab("Rank") + ylab("Predicted S") +
               geom_point(size = 0.5) + theme_bw() + ggtitle("j") + 
  theme(plot.title = element_text(face=quote(bold)))
#rank.pl.log



# ------------------------------------------------------------------------------

# write to file

lay <- matrix(nrow=4, ncol=4, byrow = TRUE,
              c(1,1,2,2,
                3,3,4,4,
                5,5,6,6,
                7,8,9,10))

tiff("../Figures/Fig_maps_of_uncertainty.tif", width=4000, height=4400, res=350,
     compression = "lzw")
  grid.arrange(plot.gr.high, plot.pl.high,
               plot.gr.S, plot.pl.S,
               plot.gr.low, plot.pl.low,
               rank.gr.lin, rank.gr.log, rank.pl.lin, rank.pl.log, 
               layout_matrix = lay,
               heights = c(1,1,1,0.8)) 
dev.off()




















