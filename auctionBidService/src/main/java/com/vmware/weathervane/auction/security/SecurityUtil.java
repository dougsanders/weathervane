/*
Copyright 2017-2019 VMware, Inc.
SPDX-License-Identifier: BSD-2-Clause
*/
/*
 * Copyright 2002-2012 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.vmware.weathervane.auction.security;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.UUID;

/**
 * Provides utilities to work with SecurityContext
 * 
 * @author Brian Dussault
 * 
 *         Adapted from SpringTrader by Harold Rosenberg
 */
public class SecurityUtil {

	public Long getAccountFromPrincipal() {
		return getPrincipal().getAccountId();
	}

	public void checkAccount(Long accountId) {
		if (accountId == null || accountId.compareTo(getAccountFromPrincipal()) != 0) {
			throw new AccessDeniedException(null);
		}
	}

	public void checkAuthToken(String token) {
		if (token == null || !token.equals(getAuthToken())) {
			throw new AccessDeniedException(null);
		}
	}

	public String getAuthToken() {
		return getPrincipal().getAuthToken();
	}

	public String getUsernameFromPrincipal() {
		return getPrincipal().getUsername();
	}

	private CustomUser getPrincipal() {
		CustomUser principal = (CustomUser) SecurityContextHolder.getContext().getAuthentication().getPrincipal();
		return principal;
	}

	public void setPhonySecurityContext() {
		SecurityContextHolder.setContext(new SecurityContext() {
			Authentication authentication = new Authentication() {

				@Override
				public String getName() {
					// TODO Auto-generated method stub
					return null;
				}

				@Override
				public void setAuthenticated(boolean isAuthenticated) throws IllegalArgumentException {
					// TODO Auto-generated method stub

				}

				@Override
				public boolean isAuthenticated() {
					// TODO Auto-generated method stub
					return false;
				}

				@Override
				public Object getPrincipal() {
					List<GrantedAuthority> authorities = new ArrayList<GrantedAuthority>();
					authorities.add(new GrantedAuthority() {
						
						@Override
						public String getAuthority() {
							return "watcher";
						}
					});
					return new CustomUser("initializationUser", "none", true, authorities, 1L, UUID.randomUUID().toString());
				}

				@Override
				public Object getDetails() {
					// TODO Auto-generated method stub
					return null;
				}

				@Override
				public Object getCredentials() {
					// TODO Auto-generated method stub
					return null;
				}

				@Override
				public Collection<? extends GrantedAuthority> getAuthorities() {
					// TODO Auto-generated method stub
					return null;
				}
			};

			@Override
			public void setAuthentication(Authentication authentication) {
			}

			@Override
			public Authentication getAuthentication() {
				return authentication;
			}
		});
	}
}
