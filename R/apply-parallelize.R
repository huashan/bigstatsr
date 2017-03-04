################################################################################

#' Split-parApply-Combine
#'
#' A Split-Apply-Combine strategy to parallelize the evaluation of a function.
#'
#' This function splits indices in parts, then apply a given function to each
#' part and finally combine the results.
#'
#' @inheritParams bigstatsr-package
#' @param p.FUN The function to be applied. It must take a
#' big.matrix.descriptor][big.matrix.descriptor-class] as first argument
#' and provide some arguments for subsetting.
#' @param p.combine function that is used by [foreach] to process the tasks
#' results as they generated. This can be specified as either a function or a
#' non-empty character string naming the function. Specifying 'c' is useful
#' for concatenating the results into a vector, for example. The values 'cbind'
#' and 'rbind' can combine vectors into a matrix. The values '+' and '*' can be
#' used to process numeric data. By default, the results are returned in a list.
#' @param ind Initial vector of subsetting indices.
#' @param ... Extra arguments to be passed to `p.FUN`.
#'
#' @return The result of [foreach].
#' @export
#' @import foreach
#'
#' @example examples/example-parallelize.R
#' @seealso [big_apply]
big_parallelize <- function(X., p.FUN, p.combine, ncores,
                            ind = cols_along(X.),
                            ...) {
  if (ncores > 1) {
    X.desc <- describe(X.)
    range.parts <- CutBySize(length(ind), nb = ncores)

    cl <- parallel::makeCluster(ncores)
    doParallel::registerDoParallel(cl)
    on.exit(parallel::stopCluster(cl), add = TRUE)

    # Microsoft R Open?
    multi <- requireNamespace("RevoUtilsMath", quietly = TRUE)

    foreach(ic = 1:ncores, .combine = p.combine) %dopar% {
      # https://www.r-bloggers.com/too-much-parallelism-is-as-bad/
      if (multi) {
        nthreads.save <- RevoUtilsMath::setMKLthreads(1)
        on.exit(RevoUtilsMath::setMKLthreads(nthreads.save), add = TRUE)
      }

      p.FUN(X.desc, ind = ind[seq2(range.parts[ic, ])], ...)
    }
  } else { # sequential
    p.FUN(X., ind = ind, ...)
  }
}

################################################################################

big_applySeq <- function(X., a.FUN, a.combine, block.size, ind, ...) {
  X <- attach.BM(X.)
  intervals <- CutBySize(length(ind), block.size)

  foreach(ic = 1:nrow(intervals), .combine = a.combine) %do% {
    a.FUN(X, ind = ind[seq2(intervals[ic, ])], ...)
  }
}

################################################################################

#' Split-Apply-Combine
#'
#' A Split-Apply-Combine strategy to apply common R functions to a `big.matrix`.
#'
#' This function splits indices in parts, then apply a given function to each
#' subset matrix and finally combine the results. If parallelization is used,
#' this function splits indices in parts for parallelization, then split again
#' them on each core, apply a given function to each part and finally combine
#' the results (on each cluster and then from each cluster).
#'
#' @inheritParams bigstatsr-package
#' @param a.FUN The function to be applied to each subset matrix.
#' It must take a `big.matrix` as first argument and `ind`, a vector of
#' indices, which are used to split the data. Example: if you want to apply
#' a function to `X[ind.row, ind.col]`, you may use
#' \code{X[ind.row, ind.col[ind]]} in `a.FUN`.
#' @param a.combine function that is used by [foreach] to process the tasks
#' results as they generated. This can be specified as either a function or a
#' non-empty character string naming the function. Specifying 'c' is useful
#' for concatenating the results into a vector, for example. The values 'cbind'
#' and 'rbind' can combine vectors into a matrix. The values '+' and '*' can be
#' used to process numeric data. By default, the results are returned in a list.
#' @param ind Initial vector of subsetting indices.
#' @param ... Extra arguments to be passed to `a.FUN`.
#'
#' @return The result of [foreach].
#' @export
#' @import foreach
#'
#' @example examples/example-apply.R
#' @seealso [big_parallelize]
big_apply <- function(X., a.FUN, a.combine,
                      ncores = 1,
                      block.size = 1000,
                      ind = cols_along(X.),
                      ...) {
  big_parallelize(X. = X.,
                  p.FUN = big_applySeq,
                  p.combine = a.combine,
                  ncores = ncores,
                  ind = ind,
                  a.FUN = a.FUN,
                  a.combine = a.combine,
                  block.size = block.size,
                  ...)
}

################################################################################