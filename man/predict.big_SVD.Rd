% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/predict.R
\name{predict.big_SVD}
\alias{predict.big_SVD}
\title{Scores of PCA}
\usage{
\method{predict}{big_SVD}(object, X = NULL, ind.row = rows_along(X),
  ind.col = cols_along(X), block.size = block_size(nrow(X)), ...)
}
\arguments{
\item{object}{A list returned by \code{big_SVD} or \code{big_randomSVD}.}

\item{X}{A \link[=FBM-class]{FBM}.}

\item{ind.row}{An optional vector of the row indices that are used.
If not specified, all rows are used. \strong{Don't use negative indices.}}

\item{ind.col}{An optional vector of the column indices that are used.
If not specified, all columns are used. \strong{Don't use negative indices.}}

\item{block.size}{Maximum number of columns read at once.
Default uses \link{block_size}.}

\item{...}{Not used.}
}
\value{
A matrix of size \eqn{n \times K} where \code{n} is the number of samples
corresponding to indices in \code{ind.row} and K the number of PCs
computed in \code{object}. If \code{X} is not specified, this just returns
the scores of the training set of \code{object}.
}
\description{
Get the scores of PCA associated with an svd decomposition (class \code{big_SVD}).
}
\examples{
set.seed(1)

X <- big_attachExtdata()
n <- nrow(X)

# Using only half of the data
ind <- sort(sample(n, n/2))

test <- big_SVD(X, fun.scaling = big_scale(), ind.row = ind)
str(test)
plot(test$u)

pca <- prcomp(X[ind, ], center = TRUE, scale. = TRUE)

# same scaling
all.equal(test$center, pca$center)
all.equal(test$scale,  pca$scale)

# scores and loadings are the same or opposite
# except for last eigenvalue which is equal to 0
# due to centering of columns
scores <- test$u \%*\% diag(test$d)
class(test)
scores2 <- predict(test) # use this function to predict scores
all.equal(scores, scores2)
dim(scores)
dim(pca$x)
tail(pca$sdev)
plot(scores2, pca$x[, 1:ncol(scores2)])
plot(test$v[1:100, ], pca$rotation[1:100, 1:ncol(scores2)])

# projecting on new data
X2 <- sweep(sweep(X[-ind, ], 2, test$center, '-'), 2, test$scale, '/')
scores.test <- X2 \%*\% test$v
ind2 <- setdiff(rows_along(X), ind)
scores.test2 <- predict(test, X, ind.row = ind2) # use this
all.equal(scores.test, scores.test2)
scores.test3 <- predict(pca, X[-ind, ])
plot(scores.test2, scores.test3[, 1:ncol(scores.test2)])
}
\seealso{
\link[stats:prcomp]{predict} \link{big_SVD} \link{big_randomSVD}
}
