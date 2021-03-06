#' Title
#'
#' @param X
#' @param fun.scaling
#' @param ind.train
#' @param block.size
#' @param K
#' @param I
#' @param extra.K
#' @param use.Eigen
#' @param backingpath
#' @param ncores
#'
#' @return
#' @export
#'
#' @examples
ParallelRandomSVD2 <- function(X, fun.scaling,
                               ind.train = seq(nrow(X)),
                               block.size = 1000,
                               K = 10,
                               I = 5,
                               extra.K = 50,
                               use.Eigen = !detect_MRO(),
                               backingpath = NULL,
                               ncores = 1,
                               tol = 1e-3,
                               maxiter = 10) {
  # parameters
  L <- K + extra.K
  L2 <- 2 * L
  n <- length(ind.train)
  m <- ncol(X)
  stopifnot((n - K) >= (I * L))

  TIME <- 0.01
  tmp.lock.name <- "mutex"
  tmp.lock.names <- paste(tmp.lock.name, Sys.getpid(), 1:4, sep = '-')
  ifelse(file.exists(tmp.lock.names), FALSE,
         file.create(tmp.lock.names))

  # shared big.matrices
  G <- big.matrix(n, L2 * (I + 1), type = "double", shared = TRUE, init = 0)
  G[, 1:L2] <- stats::rnorm(n * L2) # G0
  U1 <- big.matrix(n, L * (I + 1), type = "double", shared = TRUE)
  U2 <- big.matrix(n, L * (I + 1), type = "double", shared = TRUE)
  T.t <- big.matrix(m, L2 * (I + 1), type = "double", shared = TRUE)
  remains <- big.matrix(4, I, type = "double", shared = TRUE, init = ncores)
  conv <- big.matrix(2, 1, type = "double", shared = TRUE, init = 0)

  # descriptors
  X.desc <- describe(X)
  G.desc <- describe(G)
  U1.desc <- describe(U1)
  U2.desc <- describe(U2)
  T.t.desc <- describe(T.t)
  r.desc <- describe(remains)
  conv.desc <- describe(conv)


  intervals <- CutBySize(m, nb = ncores)

  if (is.seq <- (ncores == 1)) {
    registerDoSEQ()
  } else {
    cl <- parallel::makeCluster(ncores, outfile = "")
    doParallel::registerDoParallel(cl)
  }
  scaling <- foreach(ic = seq_len(ncores), .combine = 'cbind') %dopar% {
    lims <- intervals[ic, ]

    # get big.matrices
    X.part <- sub.big.matrix(X.desc,
                             firstCol = lims[1],
                             lastCol = lims[2],
                             backingpath = backingpath)

    G <- attach.big.matrix(G.desc)
    remains <- attach.big.matrix(r.desc)
    U2 <- attach.big.matrix(U2.desc)
    U1 <- attach.big.matrix(U1.desc)
    T.t.part <- sub.big.matrix(T.t.desc, firstRow = lims[1],
                               lastRow = lims[2])
    T.t <- attach.big.matrix(T.t.desc)
    conv <- attach.big.matrix(conv.desc)

    # https://www.r-bloggers.com/too-much-parallelism-is-as-bad/
    multi <- (!is.seq) && detect_MRO()
    if (multi) nthreads.save <- RevoUtilsMath::setMKLthreads(1)

    # scaling
    means_sds <- fun.scaling(X.part, ind.train)
    means <- means_sds$mean
    sds <- means_sds$sd
    rm(means_sds)

    # parameters
    m.part <- ncol(X.part)
    intervals <- CutBySize(m.part, block.size)
    nb.block <- nrow(intervals)

    it <- 0
    repeat {
      print(it <- it + 1)
      print("OK0")
      print(remains[,])

      # computation of G
      offset <- 0
      for (i in 1:I) {
        # get old G
        old.G <- G[, 1:L2 + offset]

        tmp.G <- matrix(0, n, L2) # new.G.part
        for (j in 1:nb.block) {
          ind <- seq2(intervals[j, ])
          tmp <- scaling(X.part[ind.train, ind], means[ind], sds[ind])
          tmp.G <- incrMat(tmp.G, mult(tmp, cross(tmp, old.G, use.Eigen),
                                       use.Eigen))
        }
        offset <- offset + L2

        print("OK1")

        # increment new G, safely
        file.lock2 <- flock::lock(tmp.lock.names[2])
        incrG(G@address, tmp.G, n, offset, L2, m)
        remains[2, i] <- remains[2, i] - 1
        flock::unlock(file.lock2)
        # wait for others at barrier
        while (remains[2, i] > 0) Sys.sleep(TIME)
      }
      print("OK2")
      remains[4, ] <- ncores

      # compute svd(G) once
      file.lock3 <- flock::lock(tmp.lock.names[3])
      if (remains[3, 1] == 1) {
        s <- c(rep(TRUE, L), rep(FALSE, L))
        cols <- seq(ncol(G))
        if (multi) RevoUtilsMath::setMKLthreads(nthreads.save)
        U2[] <- svd(G[, cols[s]], nv = 0)$u
        U1[] <- svd(G[, cols[!s]], nv = 0)$u
        if (multi) nthreads.save <- RevoUtilsMath::setMKLthreads(1)
      }
      remains[3, 1] <- remains[3, 1] - 1
      flock::unlock(file.lock3)
      # wait for others at barrier
      while (remains[3, 1] > 0) Sys.sleep(TIME)

      print("OK3")

      # compute transpose(T)
      U <- cbind(U1[,], U2[,])
      for (j in 1:nb.block) {
        ind <- seq2(intervals[j, ])
        tmp <- scaling(X.part[ind.train, ind], means[ind], sds[ind])

        T.t.part[ind, ] <- cross(tmp, U, use.Eigen)
      }

      print("OK4")

      # increment T.t, safely
      file.lock4 <- flock::lock(tmp.lock.names[4])
      if (remains[4, 1] == 1) {
        cols <- seq(ncol(T.t) / 2)
        if (multi) RevoUtilsMath::setMKLthreads(nthreads.save)
        T1.svd <- svd(T.t[, cols], nu = L, nv = L)
        T2.svd <- svd(T.t[, -cols], nu = L, nv = L)
        u1 <- mult(U1[,], T1.svd$v, use.Eigen)
        v1 = T1.svd$u
        u2 <- mult(U2[,], T2.svd$v, use.Eigen)
        v2 = T2.svd$u
        diff1 <- diffPCs(u1[, 1:K], u2)
        diff2 <- diffPCs(v1[, 1:K], v2)
        print(m1 <- max(diff1, diff2))
        if (m1 < tol) {
          conv[1] <- 1
          conv[2] <- it
          # convention of return
          U1[, 1:K] <- u1[, 1:K]
          T.t[, 1:K] <- v1[, 1:K]
          U2[1:K, 1] <- T1.svd$d[1:K]
        } else { # here we go again
          G[] <- 0
          G[, 1:L2] <- cbind(u1, u2)
          remains[-4, ] <- ncores
        }
        if (multi) nthreads.save <- RevoUtilsMath::setMKLthreads(1)
      }
      remains[4, 1] <- remains[4, 1] - 1
      print(remains[,])
      flock::unlock(file.lock4)
      # wait for others at barrier
      while (remains[4, 1] > 0) Sys.sleep(TIME)
      printf("Conv: (%s, %s)\n", conv[1], conv[2])
      printf("It: %s\n", it)

      print(cond <- conv[1] == 1 || it >= maxiter)
      if (cond) break
    }

    if (multi) RevoUtilsMath::setMKLthreads(nthreads.save)

    rbind(means, sds)
  }
  if (!is.seq) parallel::stopCluster(cl)

  # delete temporary lock files
  unlink(tmp.lock.names)

  # convention of return
  list(niter = conv[2], d = U2[1:K, 1], u = U1[, 1:K], v = T.t[, 1:K],
       means = scaling[1, ], sds = scaling[2, ])
}
